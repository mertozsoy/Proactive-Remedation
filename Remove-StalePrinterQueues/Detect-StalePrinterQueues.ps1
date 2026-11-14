<#
.SYNOPSIS
  Detection script for explicitly retired printer queues.

.DESCRIPTION
  Matches local printer inventory against approved retired server names and exact queue identities. Exits 1 if a target remains, 0 otherwise. Does not infer retirement from printer status or connectivity.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RetiredPrintServers = @()
$RetiredQueues = @()

$PackageName = 'StalePrinterQueues'
$Phase = 'Detect'
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
    $stage = 'Inventory'
    Import-Module PrintManagement -ErrorAction Stop
    $printers = @(Get-Printer -ErrorAction Stop)
    $targets = @($printers | Where-Object { Test-RetiredPrinter -Printer $_ })
    if ($targets.Count -eq 0) { Exit-Script 0 'Healthy | TargetQueues=0' }
    Exit-Script 1 "Drift | TargetQueues=$($targets.Count); Action=RemoveRetiredQueues"
}
catch { Exit-Script 1 "Error: | Stage=$stage; Code=$($_.Exception.HResult)" }
