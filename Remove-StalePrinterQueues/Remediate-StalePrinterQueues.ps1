<#
.SYNOPSIS
  Remediation script for explicitly retired printer queues.

.DESCRIPTION
  Removes approved retired queues with Remove-Printer and verifies absence. Requires confirmation that source assignments were removed. Preserves queues with visible jobs. Removal after an unreadable job inventory is disabled by default because jobs could be lost. Exits 0 only when no targeted queue remains, otherwise 1.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RetiredPrintServers = @()
$RetiredQueues = @()
$SourceAssignmentsRemoved = $false
$AllowUnverifiedJobRemoval = $false
$VerificationAttempts = 3
$VerificationDelaySeconds = 2

$PackageName = 'StalePrinterQueues'
$Phase = 'Remediate'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $logDirectory = Split-Path -Path $LogFile -Parent
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
        }
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

function Test-TargetConfiguration {
    foreach ($server in $RetiredPrintServers) {
        if ([string]::IsNullOrWhiteSpace([string]$server) -or $server -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$') {
            throw 'Invalid retired server name.'
        }
    }
    foreach ($queue in $RetiredQueues) {
        foreach ($field in @('Name', 'PortName', 'DriverName', 'Type')) {
            if ([string]::IsNullOrWhiteSpace([string]$queue[$field])) { throw 'Incomplete queue identity.' }
        }
        if ($queue.Type -notin @('Local', 'Connection')) { throw 'Invalid queue type.' }
    }
}

function Test-RetiredPrinter {
    param($Printer)
    if ([string]$Printer.Type -eq 'Connection' -and [string]$Printer.Name -match '^\\\\([^\\]+)\\[^\\]+$') {
        $serverName = $Matches[1].TrimEnd('.')
        foreach ($server in $RetiredPrintServers) {
            if ($serverName -eq ([string]$server).TrimEnd('.')) { return $true }
        }
    }
    foreach ($queue in $RetiredQueues) {
        if ($Printer.Name -eq $queue.Name -and $Printer.PortName -eq $queue.PortName -and
            $Printer.DriverName -eq $queue.DriverName -and [string]$Printer.Type -eq $queue.Type) {
            return $true
        }
    }
    return $false
}

try {
    $stage = 'Context'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.IsSystem -or $identity.User.Value -in @('S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=UserRequired'
    }
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Exit-Script 0 'NotApplicable | Context=NonElevatedUserRequired'
    }
    $stage = 'Configuration'
    Test-TargetConfiguration
    if ($RetiredPrintServers.Count -eq 0 -and $RetiredQueues.Count -eq 0) {
        Exit-Script 0 'NotApplicable | Targets=None'
    }
    if ($VerificationAttempts -lt 1 -or $VerificationAttempts -gt 10 -or
        $VerificationDelaySeconds -lt 0 -or $VerificationDelaySeconds -gt 30) {
        throw 'Invalid verification settings.'
    }
    $stage = 'Inventory'
    Import-Module PrintManagement -ErrorAction Stop
    $targets = @(Get-Printer -ErrorAction Stop | Where-Object { Test-RetiredPrinter -Printer $_ })
    if ($targets.Count -eq 0) { Exit-Script 0 'Healthy | TargetQueues=0' }
    if (-not $SourceAssignmentsRemoved) {
        Exit-Script 1 "Blocked | TargetQueues=$($targets.Count); Reason=SourceAssignmentsNotConfirmed"
    }
    $removed = 0
    $busy = 0
    $unverified = 0
    $failures = 0
    $overrideUsed = 0
    $stage = 'Removal'
    foreach ($target in $targets) {
        try {
            $current = @(Get-Printer -ErrorAction Stop | Where-Object {
                $_.Name -eq $target.Name -and $_.PortName -eq $target.PortName -and
                $_.DriverName -eq $target.DriverName -and [string]$_.Type -eq [string]$target.Type
            })
            if ($current.Count -eq 0) { continue }
            if ($current.Count -ne 1) { throw 'Ambiguous queue identity.' }
            $jobsKnown = $true
            $jobs = @()
            try { $jobs = @(Get-PrintJob -PrinterObject $current[0] -ErrorAction Stop) }
            catch {
                $jobsKnown = $false
                Write-IRTLog "JobInventoryUnavailable | Code=$($_.Exception.HResult)" 'WARN'
            }
            if ($jobsKnown -and $jobs.Count -gt 0) {
                $busy++
                continue
            }
            if (-not $jobsKnown -and -not $AllowUnverifiedJobRemoval) {
                $unverified++
                continue
            }
            if (-not $jobsKnown) { $overrideUsed++ }
            Remove-Printer -InputObject $current[0] -Confirm:$false -ErrorAction Stop
            $removed++
        }
        catch {
            $failures++
            Write-IRTLog "RemovalFailed | Code=$($_.Exception.HResult)" 'WARN'
        }
    }
    $stage = 'Verification'
    $remaining = @()
    for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
        $remaining = @(Get-Printer -ErrorAction Stop | Where-Object { Test-RetiredPrinter -Printer $_ })
        if ($remaining.Count -eq 0) { break }
        if ($attempt -lt $VerificationAttempts) { Start-Sleep -Seconds $VerificationDelaySeconds }
    }
    $summary = "Removed=$removed; Remaining=$($remaining.Count); Busy=$busy; JobsUnknown=$unverified; Errors=$failures; JobOverride=$overrideUsed"
    if ($remaining.Count -gt 0 -or $failures -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: | Stage=$stage; Code=$($_.Exception.HResult)" }
