<#
.SYNOPSIS
  Detection script for a stopped Print Spooler service or a stuck print queue.

.DESCRIPTION
  Checks the Spooler service startup mode and state. Reads Win32_PrintJob status flags
  and counts jobs that are in error state or wedged without progress.
  Exits 1 if the service is missing, disabled, stopped or the queue holds stuck jobs, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName = 'Spooler'
$StuckMinutes = 45
$ErrorStatusBits = @(2, 512)
$ActiveStatusBits = @(8, 16)

$PackageName = 'PrintSpooler'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-StuckPrintJob {
    $found = @()
    $jobs = @(Get-CimInstance -ClassName Win32_PrintJob -ErrorAction SilentlyContinue)
    foreach ($job in $jobs) {
        $mask = 0
        if ($null -ne $job.StatusMask) { $mask = [int]$job.StatusMask }
        $reason = ''
        foreach ($bit in $ErrorStatusBits) {
            if (($mask -band $bit) -eq $bit) { $reason = 'Error' }
        }
        if ($reason -eq '' -and $mask -gt 0 -and $null -ne $job.TimeSubmitted) {
            $active = $false
            foreach ($bit in $ActiveStatusBits) {
                if (($mask -band $bit) -eq $bit) { $active = $true }
            }
            if ($active -and [int]$job.PagesPrinted -eq 0) {
                $age = ([datetime]::Now - [datetime]$job.TimeSubmitted).TotalMinutes
                if ($age -ge $StuckMinutes) { $reason = 'Wedged' }
            }
        }
        if ($reason -ne '') {
            $found += [pscustomobject]@{ JobId = [int]$job.JobId; Reason = $reason }
        }
    }
    $found
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient' }

    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($null -eq $service) { Exit-Script 1 'Drift | Service=Missing; Jobs=0; StuckJobs=0' }

    $jobs = @(Get-CimInstance -ClassName Win32_PrintJob -ErrorAction SilentlyContinue)
    $stuck = @(Get-StuckPrintJob)
    $jobIds = @($stuck | Select-Object -ExpandProperty JobId -Unique)

    $summary = 'Service={0}; StartMode={1}; Jobs={2}; StuckJobs={3}' -f $service.State, $service.StartMode, $jobs.Count, $stuck.Count
    if ($jobIds.Count -gt 0) { $summary = $summary + '; JobIds=' + ($jobIds -join ',') }

    if ($service.StartMode -eq 'Disabled' -or $service.State -ne 'Running' -or $stuck.Count -gt 0) {
        Exit-Script 1 "Drift | $summary"
    }

    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Detect; HResult=$($_.Exception.HResult)" }
