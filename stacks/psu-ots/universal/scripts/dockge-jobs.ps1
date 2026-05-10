#Requires -Version 5.1
<#
.SYNOPSIS
    Dockge / NAS compliance jobs for PowerShell Universal (Phase 2 — fire-and-forget).

.DESCRIPTION
    Each Invoke-PSUJob_* queues a background job that writes one timestamped JSON file
    under /data/reports (48h retention). Jobs avoid requiring docker.sock inside the
    PSU container: prefer Dockge HTTP API, curl, and /nas-repo filesystem reads.

.NOTES
    Copy into data/Repository/.universal/scripts/ on the NAS. Register schedules in PSU.
    Environment: DOCKGE_REPO_ROOT, PSU_STACK_ROOT, DOCKGE_BASE_URL, DOCKGE_USERNAME, DOCKGE_PASSWORD.
#>

$ErrorActionPreference = "Stop"

function Get-PSUReportsRoot {
    $r = $env:PSU_REPORTS_ROOT
    if ([string]::IsNullOrWhiteSpace($r)) { $r = "/data/reports" }
    return $r
}

function Initialize-PSUReportsRoot {
    $root = Get-PSUReportsRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Clear-PSUReportRetention {
    param(
        [int]$RetentionHours = 48
    )
    $root = Get-PSUReportsRoot
    if (-not (Test-Path -LiteralPath $root)) { return }
    $cutoff = (Get-Date).AddHours(-1 * $RetentionHours)
    Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq ".json" -and $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
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

function Invoke-Sh {
    param([string]$Command)
    & bash -lc $Command 2>&1
}

function Start-PSUJsonReportJob {
    param(
        [string]$ReportBaseName,
        [scriptblock]$Worker
    )
    Initialize-PSUReportsRoot | Out-Null
    Clear-PSUReportRetention | Out-Null
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $root = Get-PSUReportsRoot
    $outPath = Join-Path $root ("{0}-{1}.json" -f $ReportBaseName, $ts)
    $repo = Get-RepoRoot
    $stacks = Get-StackRoot
    $dockge = $env:DOCKGE_BASE_URL
    $du = $env:DOCKGE_USERNAME
    $dp = $env:DOCKGE_PASSWORD
    $null = Start-Job -ScriptBlock $Worker -ArgumentList @($outPath, $repo, $stacks, $dockge, $du, $dp)
    return @{ queued = $true; reportPath = $outPath; timestampUnix = $ts }
}

function Invoke-PSUJob_ImageDrift {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $ErrorActionPreference = "Continue"
        $obj = [ordered]@{
            job            = "image-drift"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            stacks         = @()
            floatingTags   = @()
            dockgeApi      = $null
            notes          = @()
        }
        try {
            if (Test-Path -LiteralPath $Stacks) {
                Get-ChildItem -LiteralPath $Stacks -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $compose = Join-Path $_.FullName "compose.yaml"
                    if (-not (Test-Path -LiteralPath $compose)) { $compose = Join-Path $_.FullName "docker-compose.yaml" }
                    if (-not (Test-Path -LiteralPath $compose)) { return }
                    $txt = Get-Content -LiteralPath $compose -Raw -ErrorAction SilentlyContinue
                    if ($null -eq $txt) { return }
                    foreach ($m in [regex]::Matches($txt, '(?m)^\s*image:\s*([^\s#]+)')) {
                        $img = $m.Groups[1].Value.Trim('"''')
                        if ($img -match ':latest$' -or $img -notmatch ':') {
                            $obj.floatingTags += [ordered]@{ stack = $_.Name; image = $img }
                        }
                    }
                    $obj.stacks += [ordered]@{ name = $_.Name; compose = $compose }
                }
            }
        }
        catch { $obj.notes += $_.Exception.Message }
        if (-not [string]::IsNullOrWhiteSpace($DockgeBase) -and -not [string]::IsNullOrWhiteSpace($DockgeUser)) {
            try {
                $pair = "{0}:{1}" -f $DockgeUser, $DockgePass
                $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
                $uri = ($DockgeBase.TrimEnd("/") + "/api/stacks")
                $obj.dockgeApi = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Basic $b64" } -TimeoutSec 20 -ErrorAction Stop
            }
            catch { $obj.notes += ("dockge api: " + $_.Exception.Message) }
        }
        else { $obj.notes += "Dockge credentials not set; filesystem scan only." }
        ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "image-drift" -Worker $worker)
}

function Invoke-PSUJob_NasHealth {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $obj = [ordered]@{
            job            = "nas-health"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            diskFree       = $null
            mdstat         = $null
            loadavg        = $null
            btrfs          = $null
            notes          = @()
        }
        try { $obj.diskFree = (Invoke-Sh "df -hP 2>/dev/null | head -n 30") } catch { $obj.notes += $_.Exception.Message }
        try { $obj.mdstat = (Invoke-Sh "cat /proc/mdstat 2>/dev/null") } catch { }
        try { $obj.loadavg = (Invoke-Sh "cat /proc/loadavg 2>/dev/null") } catch { }
        try { $obj.btrfs = (Invoke-Sh "btrfs scrub status / 2>/dev/null | head -n 20") } catch { }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "nas-health" -Worker $worker)
}

function Invoke-PSUJob_IngressValidator {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $obj = [ordered]@{
            job            = "ingress-validator"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            traefikPingMs  = $null
            haproxyLines   = 0
            notes          = @()
        }
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Invoke-WebRequest -Uri "http://127.0.0.1:5000/" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            $sw.Stop()
            $obj.traefikPingMs = [int]$sw.ElapsedMilliseconds
        }
        catch { $obj.notes += ("local psu: " + $_.Exception.Message) }
        $cfg = Join-Path $Repo "stacks/_haproxy/haproxy.cfg"
        if (Test-Path -LiteralPath $cfg) {
            $obj.haproxyLines = (Get-Content -LiteralPath $cfg | Measure-Object -Line).Lines
        }
        ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "ingress-validator" -Worker $worker)
}

function Invoke-PSUJob_DockerLatency {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $obj = [ordered]@{
            job            = "docker-latency"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            dockgeMs       = $null
            notes          = @()
        }
        if (-not [string]::IsNullOrWhiteSpace($DockgeBase)) {
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $pair = "{0}:{1}" -f $DockgeUser, $DockgePass
                $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
                $null = Invoke-WebRequest -Uri ($DockgeBase.TrimEnd("/") + "/") -Headers @{ Authorization = "Basic $b64" } -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
                $sw.Stop()
                $obj.dockgeMs = [int]$sw.ElapsedMilliseconds
            }
            catch { $obj.notes += $_.Exception.Message }
        }
        else { $obj.notes += "DOCKGE_BASE_URL unset" }
        ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "docker-latency" -Worker $worker)
}

function Invoke-PSUJob_PSUSelfHealth {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $dataRoot = "/data"
        $obj = [ordered]@{
            job            = "psu-self-health"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            dataDiskUsage  = $null
            gitQuick       = $null
            notes          = @()
        }
        try { $obj.dataDiskUsage = (Invoke-Sh "du -sh $dataRoot 2>/dev/null") } catch { $obj.notes += $_.Exception.Message }
        try {
            $obj.gitQuick = (Invoke-Sh "git -C `"$Repo`" status -sb --porcelain 2>/dev/null | head -n 40")
        }
        catch { }
        ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "psu-self-health" -Worker $worker)
}

function Invoke-PSUJob_StackDependencies {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $graph = [ordered]@{ nodes = @(); edges = @(); cycles = @(); orphans = @(); notes = @("Cycle detection: use inventory analyzer dependency graph on repo host for authoritative results.") }
        $adj = @{}
        if (-not (Test-Path -LiteralPath $Stacks)) {
            ($graph | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $OutPath -Encoding UTF8
            return
        }
        Get-ChildItem -LiteralPath $Stacks -Directory | ForEach-Object {
            $name = $_.Name
            if ($name.StartsWith("_")) { return }
            $graph.nodes += $name
            $adj[$name] = New-Object "System.Collections.Generic.List[string]"
            $compose = Join-Path $_.FullName "compose.yaml"
            if (-not (Test-Path -LiteralPath $compose)) { $compose = Join-Path $_.FullName "docker-compose.yaml" }
            if (-not (Test-Path -LiteralPath $compose)) { return }
            $lines = Get-Content -LiteralPath $compose -ErrorAction SilentlyContinue
            $inDepends = $false
            foreach ($line in $lines) {
                if ($line -match '^\s*depends_on:\s*$') { $inDepends = $true; continue }
                if ($inDepends) {
                    if ($line -match '^\s*-\s*(\S+)') {
                        $dep = $Matches[1].Trim('"''')
                        $graph.edges += [ordered]@{ from = $name; to = $dep }
                        [void]$adj[$name].Add($dep)
                        continue
                    }
                    if ($line -match '^\S') { $inDepends = $false }
                }
            }
        }
        foreach ($n in $graph.nodes) {
            if (-not $adj.ContainsKey($n)) { $adj[$n] = New-Object "System.Collections.Generic.List[string]" }
        }
        foreach ($n in $graph.nodes) {
            $incoming = @($graph.edges | Where-Object { $_.to -eq $n }).Count
            $outgoing = @($graph.edges | Where-Object { $_.from -eq $n }).Count
            if ($incoming -eq 0 -and $outgoing -eq 0 -and $graph.nodes.Count -gt 1) { $graph.orphans += $n }
        }
        ($graph | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "stack-dependencies" -Worker $worker)
}

function Invoke-PSUJob_SecurityScanner {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $obj = [ordered]@{
            job            = "security-scanner"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            trivy          = $null
            notes          = @()
        }
        $tv = Invoke-Sh "command -v trivy >/dev/null 2>&1 && trivy fs --scanners vuln --severity HIGH,CRITICAL --quiet --format json `"$Repo`" 2>/dev/null | head -c 400000"
        if ([string]::IsNullOrWhiteSpace($tv)) { $obj.notes += "trivy not installed or scan skipped" }
        else { $obj.trivy = $tv }
        ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "security-scanner" -Worker $worker)
}

function Invoke-PSUJob_BackupSnapshot {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $obj = [ordered]@{
            job            = "backup-snapshot"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            manifest       = @()
        }
        $targets = @(
            (Join-Path $Repo ".pre-commit-config.yaml"),
            (Join-Path $Repo "stacks/_haproxy/haproxy.cfg")
        )
        foreach ($t in $targets) {
            if (Test-Path -LiteralPath $t) {
                $h = Get-FileHash -LiteralPath $t -Algorithm SHA256
                $obj.manifest += [ordered]@{ path = $t; sha256 = $h.Hash; size = (Get-Item $t).Length }
            }
        }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "backup-snapshot" -Worker $worker)
}

function Invoke-PSUJob_AutoRemediation {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $enabled = $env:PSU_REMEDIATION_ENABLED -eq "1"
        $obj = [ordered]@{
            job            = "auto-remediation"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            enabled        = [bool]$enabled
            actions        = @()
        }
        if (-not $enabled) {
            $obj.actions += "Remediation disabled (set PSU_REMEDIATION_ENABLED=1 after review)."
            ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $OutPath -Encoding UTF8
            return
        }
        $obj.actions += "No automatic host mutations from container (safety). Review JSON alerts manually."
        ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "auto-remediation" -Worker $worker)
}

function Invoke-PSUJob_GitOpsSync {
    $worker = {
        param($OutPath, $Repo, $Stacks, $DockgeBase, $DockgeUser, $DockgePass)
        $obj = [ordered]@{
            job            = "gitops-sync"
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            enabled        = ($env:PSU_GITOPS_ENABLED -eq "1")
            message        = "Disabled by default. Requires /nas-repo :rw and GitHub token outside container."
        }
        ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    return (Start-PSUJsonReportJob -ReportBaseName "gitops-sync" -Worker $worker)
}

Write-Output "dockge-jobs.ps1: loaded Phase 2 jobs. Call Invoke-PSUJob_* from PSU schedules (each queues a background JSON report)."
