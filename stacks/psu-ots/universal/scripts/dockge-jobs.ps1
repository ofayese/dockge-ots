#Requires -Version 5.1
<#
.SYNOPSIS
    Scheduled Dockge compliance jobs (template for PowerShell Universal).

.NOTES
    Copy this tree into `data/Repository/.universal/` on the NAS (see README).
    Wire schedules in the PSU admin UI. Jobs should write JSON/text under a
    writable reports path in the container (e.g. /data/reports/).
#>

$ErrorActionPreference = "Stop"
Write-Output "dockge-jobs.ps1: template — register hourly pre-commit, 15m shell tests, 10m analyzer, 5m drift in PSU."
