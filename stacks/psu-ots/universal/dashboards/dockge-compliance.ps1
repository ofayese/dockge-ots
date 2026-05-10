#Requires -Version 5.1
<#
.SYNOPSIS
    Dockge NOC dashboard panels (Phase 2) — reads JSON from /data/reports.

.DESCRIPTION
    When Universal Dashboard cmdlets are available, registers a dashboard page
    with New-UDDynamic + AutoRefresh reading the latest job outputs.
    Otherwise exposes helper functions for manual PSU page wiring.

.NOTES
    Copy into data/Repository/.universal/dashboards/. Requires reports from dockge-jobs.ps1.
#>

$ErrorActionPreference = "Stop"

function Get-PSUReportsRoot {
    $r = $env:PSU_REPORTS_ROOT
    if ([string]::IsNullOrWhiteSpace($r)) { $r = "/data/reports" }
    return $r
}

function Get-DockgeLatestReportObject {
    param([Parameter(Mandatory = $true)][string]$Prefix)
    $root = Get-PSUReportsRoot
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $f = Get-ChildItem -LiteralPath $root -Filter ("$Prefix*.json") -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $f) { return $null }
    try { return (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) }
    catch { return @{ parseError = $_.Exception.Message; file = $f.Name } }
}

function New-DockgeReportTable {
    param($Object)
    if ($null -eq $Object) { return @([ordered]@{ info = "no report yet" }) }
    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        return @($Object.PSObject.Properties | ForEach-Object {
                [ordered]@{ name = $_.Name; value = ($_.Value | Out-String).Trim() }
            })
    }
    if ($Object -is [hashtable] -or $Object -is [System.Collections.IDictionary]) {
        return @($Object.GetEnumerator() | ForEach-Object { [ordered]@{ name = $_.Name; value = ($_.Value | Out-String).Trim() } })
    }
    return @($Object)
}

if (Get-Command New-PSUDashboard -ErrorAction SilentlyContinue) {
    try {
        New-PSUDashboard -Name "DockgeCompliance" -BaseUrl "/dockge-compliance" -Framework "Universal" -Content {
        New-UDRow -Columns {
            New-UDColumn -LargeSize 6 -Content {
                New-UDHeading -Text "Panel A — Image drift"
                New-UDDynamic -Content {
                    $d = Get-DockgeLatestReportObject -Prefix "image-drift"
                    New-UDTable -Data (New-DockgeReportTable -Object $d) -Dense
                } -AutoRefresh -AutoRefreshInterval 60
            }
            New-UDColumn -LargeSize 6 -Content {
                New-UDHeading -Text "Panel B — NAS health"
                New-UDDynamic -Content {
                    $d = Get-DockgeLatestReportObject -Prefix "nas-health"
                    New-UDTable -Data (New-DockgeReportTable -Object $d) -Dense
                } -AutoRefresh -AutoRefreshInterval 60
            }
        }
        New-UDRow -Columns {
            New-UDColumn -LargeSize 6 -Content {
                New-UDHeading -Text "Panel C — Ingress"
                New-UDDynamic -Content {
                    $d = Get-DockgeLatestReportObject -Prefix "ingress-validator"
                    New-UDTable -Data (New-DockgeReportTable -Object $d) -Dense
                } -AutoRefresh -AutoRefreshInterval 120
            }
            New-UDColumn -LargeSize 6 -Content {
                New-UDHeading -Text "Panel D — Docker / Dockge latency"
                New-UDDynamic -Content {
                    $d = Get-DockgeLatestReportObject -Prefix "docker-latency"
                    New-UDTable -Data (New-DockgeReportTable -Object $d) -Dense
                } -AutoRefresh -AutoRefreshInterval 120
            }
        }
        New-UDRow -Columns {
            New-UDColumn -LargeSize 6 -Content {
                New-UDHeading -Text "Panel E — PSU self-health"
                New-UDDynamic -Content {
                    $d = Get-DockgeLatestReportObject -Prefix "psu-self-health"
                    New-UDTable -Data (New-DockgeReportTable -Object $d) -Dense
                } -AutoRefresh -AutoRefreshInterval 120
            }
            New-UDColumn -LargeSize 6 -Content {
                New-UDHeading -Text "Panel F — Stack dependencies"
                New-UDDynamic -Content {
                    $d = Get-DockgeLatestReportObject -Prefix "stack-dependencies"
                    New-UDTable -Data (New-DockgeReportTable -Object $d) -Dense
                } -AutoRefresh -AutoRefreshInterval 300
            }
        }
        New-UDRow -Columns {
            New-UDColumn -LargeSize 12 -Content {
                New-UDHeading -Text "Panel G — Security (trivy)"
                New-UDDynamic -Content {
                    $d = Get-DockgeLatestReportObject -Prefix "security-scanner"
                    New-UDTable -Data (New-DockgeReportTable -Object $d) -Dense
                } -AutoRefresh -AutoRefreshInterval 3600
            }
        }
    }
    }
    catch {
        Write-Warning "dockge-compliance.ps1: dashboard registration failed: $($_.Exception.Message)"
    }
}
else {
    Write-Output "dockge-compliance.ps1: Universal Dashboard cmdlets not present — use Get-DockgeLatestReportObject in custom PSU pages."
}
