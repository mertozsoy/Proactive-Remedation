<#
.SYNOPSIS
  Remediation script for a stopped Print Spooler service or a stuck print queue.

.DESCRIPTION
  Re-enables a disabled Spooler service, starts it and waits for the running state.
  Cancels print jobs that sit in error state or make no progress, then verifies the queue.
  Exits 0 when the service runs and no stuck job remains, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName = 'Spooler'
$RecoveryStartMode = 'Automatic'
$StuckMinutes = 45
$ClearStuckJobs = $true
$PurgeSpoolFolder = $false
$StartTimeoutSeconds = 30
$ErrorStatusBits = @(2, 512)
$ActiveStatusBits = @(8, 16)

$PackageName = 'PrintSpooler'
$Phase = 'Remediate'
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

function Remove-StuckPrintJob {
    param([int]$JobId)
    $removed = $false
    $printers = @(Get-Printer -ErrorAction SilentlyContinue)
    foreach ($printer in $printers) {
        $match = @(Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue | Where-Object { [int]$_.JobId -eq $JobId })
        if ($match.Count -eq 0) { continue }
        Remove-PrintJob -InputObject $match[0] -ErrorAction Stop
        $removed = $true
        break
    }
    $removed
}

function Clear-SpoolFolder {
    $folder = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
    if (-not (Test-Path -LiteralPath $folder)) { return 0 }
    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
        $count++
    }
    $count
}

function Wait-SpoolerRunning {
    param([int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $state = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue).State
        if ($state -eq 'Running') { return $true }
        Start-Sleep -Seconds 2
    }
    $false
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient' }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -ne 'S-1-5-18' -or -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=RequiresSystemAnd64BitPowerShell'
    }

    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($null -eq $service) { Exit-Script 1 'Failed | Reason=SpoolerServiceMissing; Action=None' }

    $modeFixed = $false
    if ($service.StartMode -eq 'Disabled') {
        try {
            Set-Service -Name $ServiceName -StartupType $RecoveryStartMode -ErrorAction Stop
            $verifiedMode = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop).StartMode
            if ($verifiedMode -eq 'Auto') { $modeFixed = $true }
            Write-IRTLog "StartMode | New=$verifiedMode"
        }
        catch {
            Write-IRTLog "StartModeFailed | HResult=$($_.Exception.HResult)" 'ERROR'
        }
    }

    $serviceStarted = $false
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($service.State -ne 'Running') {
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            $serviceStarted = $true
            Write-IRTLog 'ServiceStartRequested'
        }
        catch {
            Write-IRTLog "ServiceStartFailed | HResult=$($_.Exception.HResult)" 'ERROR'
        }
        $null = Wait-SpoolerRunning -TimeoutSeconds $StartTimeoutSeconds
    }

    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($service.State -ne 'Running') {
        Exit-Script 1 ('Failed | Reason=ServiceNotRunning; StartMode={0}; State={1}; ModeFixed={2}' -f $service.StartMode, $service.State, $modeFixed)
    }

    $cancelled = @()
    $notCancelled = @()
    $stuck = @(Get-StuckPrintJob)
    if ($ClearStuckJobs) {
        foreach ($item in $stuck) {
            try {
                if (Remove-StuckPrintJob -JobId $item.JobId) {
                    $cancelled += $item.JobId
                    Write-IRTLog "JobCancelled | JobId=$($item.JobId); Reason=$($item.Reason)"
                }
                else {
                    $notCancelled += $item.JobId
                    Write-IRTLog "JobNotCancelled | JobId=$($item.JobId); Reason=PrinterNotFound" 'WARN'
                }
            }
            catch {
                $notCancelled += $item.JobId
                Write-IRTLog "JobCancelFailed | JobId=$($item.JobId); HResult=$($_.Exception.HResult)" 'ERROR'
            }
        }
    }

    $purged = 0
    if ($PurgeSpoolFolder -and -not $ClearStuckJobs) {
        Write-IRTLog 'SpoolFolderSkipped | Reason=ClearStuckJobsDisabled' 'WARN'
    }
    elseif ($PurgeSpoolFolder -and $notCancelled.Count -gt 0) {
        try {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            $purged = Clear-SpoolFolder
            Start-Service -Name $ServiceName -ErrorAction Stop
            $null = Wait-SpoolerRunning -TimeoutSeconds $StartTimeoutSeconds
            Write-IRTLog "SpoolFolderPurged | Files=$purged"
        }
        catch {
            Write-IRTLog "SpoolFolderPurgeFailed | HResult=$($_.Exception.HResult)" 'ERROR'
        }
    }

    $remaining = @(Get-StuckPrintJob)
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop

    $summary = 'Service={0}; StartMode={1}; ModeFixed={2}; ServiceStarted={3}; Cancelled={4}; Remaining={5}' -f $service.State, $service.StartMode, $modeFixed, $serviceStarted, $cancelled.Count, $remaining.Count
    if ($cancelled.Count -gt 0) { $summary = $summary + '; JobIds=' + ($cancelled -join ',') }
    if ($purged -gt 0) { $summary = $summary + '; SpoolFilesPurged=' + $purged }

    if ($service.State -ne 'Running' -or $remaining.Count -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
