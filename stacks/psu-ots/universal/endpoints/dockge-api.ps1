#Requires -Version 5.1
<#
.SYNOPSIS
    REST API endpoints for Dockge / NAS automation (Phase 2).

.DESCRIPTION
    Registers PSU endpoints under /api/v1/*. Each route validates
    Authorization: Bearer <token> against $env:PSU_AUTH_TOKEN (fail closed if unset).

.NOTES
    Copy into data/Repository/.universal/endpoints/. Requires PSU (New-PSUEndpoint).
    Optional: dot-source ../scripts/dockge-jobs.ps1 before this file so POST routes can queue jobs.
#>

$ErrorActionPreference = "Stop"

function Get-PSUReportsRoot {
    $r = $env:PSU_REPORTS_ROOT
    if ([string]::IsNullOrWhiteSpace($r)) { $r = "/data/reports" }
    return $r
}

function Get-RepoRoot {
    $p = $env:DOCKGE_REPO_ROOT
    if ([string]::IsNullOrWhiteSpace($p)) { $p = "/nas-repo" }
    return $p
}

function Get-StackRoot {
    $p = $env:PSU_STACK_ROOT
    if ([string]::IsNullOrWhiteSpace($p)) { $p = (Join-Path (Get-RepoRoot) "stacks") }
    return $p
}

function Test-PSUBearerAuth {
    if ([string]::IsNullOrWhiteSpace($env:PSU_AUTH_TOKEN)) {
        if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
            return (New-PSUApiResponse -StatusCode 503 -Body '{"error":"PSU_AUTH_TOKEN is not set on the container environment."}' -ContentType "application/json")
        }
        return '{"error":"PSU_AUTH_TOKEN is not set on the container environment."}'
    }
    $hdr = $null
    if ($Headers -and $Headers.Authorization) { $hdr = $Headers.Authorization }
    if ([string]::IsNullOrWhiteSpace($hdr) -or $hdr -notmatch '^\s*Bearer\s+(\S+)\s*$') {
        if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
            return (New-PSUApiResponse -StatusCode 401 -Body '{"error":"Missing or invalid Authorization header (expected Bearer token)."}' -ContentType "application/json")
        }
        return '{"error":"Missing or invalid Authorization header (expected Bearer token)."}'
    }
    $tok = $Matches[1].Trim()
    if ($tok -cne $env:PSU_AUTH_TOKEN) {
        if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
            return (New-PSUApiResponse -StatusCode 401 -Body '{"error":"Bearer token mismatch."}' -ContentType "application/json")
        }
        return '{"error":"Bearer token mismatch."}'
    }
    return $null
}

function Get-LatestReportJson {
    param([string]$Prefix)
    $root = Get-PSUReportsRoot
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $f = Get-ChildItem -LiteralPath $root -Filter ("$Prefix*.json") -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $f) { return $null }
    return (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8)
}

function Invoke-DockgeStacksList {
    $base = $env:DOCKGE_BASE_URL
    $u = $env:DOCKGE_USERNAME
    $p = $env:DOCKGE_PASSWORD
    if ([string]::IsNullOrWhiteSpace($base) -or [string]::IsNullOrWhiteSpace($u)) { return $null }
    try {
        $pair = "{0}:{1}" -f $u, $p
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        $uri = ($base.TrimEnd("/") + "/api/stacks")
        return (Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Basic $b64" } -TimeoutSec 25 -ErrorAction Stop)
    }
    catch { return @{ error = $_.Exception.Message } }
}

if ($PSScriptRoot) {
    $jobs = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts/dockge-jobs.ps1"
    if (Test-Path -LiteralPath $jobs) {
        . $jobs
    }
}

if (Get-Command New-PSUEndpoint -ErrorAction SilentlyContinue) {

    New-PSUEndpoint -Url "/api/v1/stacks/status" -Method GET -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        $stacksRoot = Get-StackRoot
        $dirs = @()
        if (Test-Path -LiteralPath $stacksRoot) {
            $dirs = @(Get-ChildItem -LiteralPath $stacksRoot -Directory | Where-Object { -not $_.Name.StartsWith("_") } | ForEach-Object { $_.Name })
        }
        $dockge = Invoke-DockgeStacksList
        $drift = Get-LatestReportJson -Prefix "image-drift"
        $health = Get-LatestReportJson -Prefix "nas-health"
        $obj = [ordered]@{
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            filesystemStacks = $dirs
            dockgeApi        = $dockge
            latestImageDrift = if ($drift) { ($drift | ConvertFrom-Json -ErrorAction SilentlyContinue) } else { $null }
            latestNasHealth  = if ($health) { ($health | ConvertFrom-Json -ErrorAction SilentlyContinue) } else { $null }
        }
        $obj | ConvertTo-Json -Depth 12
    }

    New-PSUEndpoint -Url "/api/v1/stacks/restart-all" -Method POST -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        if ($env:PSU_ALLOW_STACK_RESTART -ne "1") {
            if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
                return (New-PSUApiResponse -StatusCode 403 -Body '{"error":"Set PSU_ALLOW_STACK_RESTART=1 on the container to acknowledge destructive restarts."}' -ContentType "application/json")
            }
            return '{"error":"PSU_ALLOW_STACK_RESTART not enabled"}'
        }
        if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
            return (New-PSUApiResponse -StatusCode 503 -Body '{"error":"Stack restart from PSU container is not implemented (no docker.sock). Use Dockge UI or host automation."}' -ContentType "application/json")
        }
        return '{"error":"not_implemented"}'
    }

    New-PSUEndpoint -Url "/api/v1/ingress/validate" -Method POST -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        if (-not (Get-Command Invoke-PSUJob_IngressValidator -ErrorAction SilentlyContinue)) {
            return '{"error":"dockge-jobs.ps1 not loaded"}'
        }
        $q = Invoke-PSUJob_IngressValidator
        $q | ConvertTo-Json -Depth 5
    }

    New-PSUEndpoint -Url "/api/v1/nas/health" -Method GET -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        $latest = Get-LatestReportJson -Prefix "nas-health"
        $lat = Get-LatestReportJson -Prefix "docker-latency"
        $obj = [ordered]@{
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            latestNasHealthReport = if ($latest) { ($latest | ConvertFrom-Json -ErrorAction SilentlyContinue) } else { $null }
            latestDockerLatency   = if ($lat) { ($lat | ConvertFrom-Json -ErrorAction SilentlyContinue) } else { $null }
        }
        $obj | ConvertTo-Json -Depth 10
    }

    New-PSUEndpoint -Url "/api/v1/analyzer/report" -Method GET -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        $cached = Join-Path (Get-PSUReportsRoot) "analyzer-latest.json"
        if (Test-Path -LiteralPath $cached) {
            return (Get-Content -LiteralPath $cached -Raw -Encoding UTF8)
        }
        $repo = Get-RepoRoot
        $inv = Join-Path $repo "docs/hive/tools/inventory.py"
        if (-not (Test-Path -LiteralPath $inv)) {
            if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
                return (New-PSUApiResponse -StatusCode 404 -Body '{"error":"inventory.py not found under /nas-repo"}' -ContentType "application/json")
            }
            return '{"error":"inventory.py not found"}'
        }
        try {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            $tmpErr = [System.IO.Path]::GetTempFileName()
            $p = Start-Process -FilePath "python3" -ArgumentList @($inv, "--all", "--analyze", "--json") -WorkingDirectory $repo -PassThru -NoNewWindow -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            if ($null -eq $p) {
                Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
                return (@{ error = "failed to start python3" } | ConvertTo-Json)
            }
            if (-not $p.WaitForExit(120000)) {
                try { $p.Kill() } catch { }
                Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
                if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
                    return (New-PSUApiResponse -StatusCode 504 -Body '{"error":"inventory analyzer timed out"}' -ContentType "application/json")
                }
                return '{"error":"timeout"}'
            }
            if ($p.ExitCode -ne 0) {
                $stderr = ""
                if (Test-Path $tmpErr) { $stderr = (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue) }
                Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
                return (@{ error = "inventory failed"; exitCode = $p.ExitCode; stderr = $stderr } | ConvertTo-Json -Depth 4)
            }
            $stdout = Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8
            Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
            $rr = Get-PSUReportsRoot
            if (-not (Test-Path -LiteralPath $rr)) { New-Item -ItemType Directory -Path $rr -Force | Out-Null }
            $stdout | Set-Content -LiteralPath (Join-Path $rr "analyzer-latest.json") -Encoding UTF8
            return $stdout
        }
        catch {
            return (@{ error = $_.Exception.Message } | ConvertTo-Json)
        }
    }

    New-PSUEndpoint -Url "/api/v1/git/status" -Method GET -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        $repo = Get-RepoRoot
        $branch = ""
        $porcelain = ""
        $aheadBehind = ""
        try { $branch = (& git -C $repo rev-parse --abbrev-ref HEAD 2>$null) } catch { }
        try { $porcelain = (& git -C $repo status --porcelain -b 2>$null | Out-String).Trim() } catch { }
        try {
            $upstream = & git -C $repo rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null
            if ($upstream) {
                $aheadBehind = (& git -C $repo rev-list --left-right --count "${upstream}...HEAD" 2>$null) -join " "
            }
        }
        catch { }
        [ordered]@{
            repo            = $repo
            branch          = $branch
            statusPorcelain = $porcelain
            aheadBehind     = $aheadBehind
            generatedAtUtc  = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json -Depth 4
    }

    New-PSUEndpoint -Url "/api/v1/alerts/active" -Method GET -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        $root = Get-PSUReportsRoot
        $items = @()
        if (Test-Path -LiteralPath $root) {
            $items = @(Get-ChildItem -LiteralPath $root -Filter "*.json" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 25 | ForEach-Object {
                [ordered]@{ name = $_.Name; lastWriteUtc = $_.LastWriteTimeUtc.ToString("o"); sizeBytes = $_.Length }
            })
        }
        [ordered]@{ reports = $items; generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json -Depth 6
    }

    New-PSUEndpoint -Url "/api/v1/remediation/run" -Method POST -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        if ($env:PSU_REMEDIATION_ENABLED -ne "1") {
            if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
                return (New-PSUApiResponse -StatusCode 403 -Body '{"error":"PSU_REMEDIATION_ENABLED is not 1"}' -ContentType "application/json")
            }
            return '{"error":"remediation disabled"}'
        }
        if (Get-Command Invoke-PSUJob_AutoRemediation -ErrorAction SilentlyContinue) {
            $q = Invoke-PSUJob_AutoRemediation
            return ($q | ConvertTo-Json -Depth 5)
        }
        return '{"error":"jobs not loaded"}'
    }

    New-PSUEndpoint -Url "/api/v1/gitops/sync" -Method POST -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
            return (New-PSUApiResponse -StatusCode 501 -Body '{"error":"GitOps PR automation not implemented in-container (needs :rw repo + PAT on host)."}' -ContentType "application/json")
        }
        return '{"error":"not_implemented"}'
    }

    New-PSUEndpoint -Url "/api/v1/provision/stack" -Method POST -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
            return (New-PSUApiResponse -StatusCode 501 -Body '{"error":"Stack provisioning API not implemented (template placeholder)."}' -ContentType "application/json")
        }
        return '{"error":"not_implemented"}'
    }

    New-PSUEndpoint -Url "/api/v1/backup/run" -Method POST -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        if (-not (Get-Command Invoke-PSUJob_BackupSnapshot -ErrorAction SilentlyContinue)) {
            return '{"error":"dockge-jobs.ps1 not loaded"}'
        }
        $q = Invoke-PSUJob_BackupSnapshot
        $q | ConvertTo-Json -Depth 5
    }

    New-PSUEndpoint -Url "/api/v1/restore/request" -Method POST -Endpoint {
        $auth = Test-PSUBearerAuth
        if ($null -ne $auth) { return $auth }
        if (Get-Command New-PSUApiResponse -ErrorAction SilentlyContinue) {
            return (New-PSUApiResponse -StatusCode 501 -Body '{"error":"Restore orchestration not implemented (operator restores from Hyper Backup / snapshots)."}' -ContentType "application/json")
        }
        return '{"error":"not_implemented"}'
    }
}
else {
    Write-Warning "New-PSUEndpoint not available (load this file inside PowerShell Universal)."
}
