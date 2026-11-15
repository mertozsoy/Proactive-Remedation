<#
.SYNOPSIS
  Detection script for a hung msiexec process or a stale Windows Installer InProgress key.

.DESCRIPTION
  Reads the InProgress key under the Windows Installer registry root and lists msiexec processes that carry a real install command line.
  An installer process younger than $HungProcessMinutes is treated as a running installation and is not flagged.
  Exits 1 if the key is left behind with no installation running, or if an install process runs longer than the threshold, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$HungProcessMinutes = 90
$InProgressKey      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress'

$PackageName = 'Msiexec1618'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

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

function Get-InstallProcess {
    $list = @()
    $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='msiexec.exe'" -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        $commandLine = [string]$process.CommandLine
        if (-not $commandLine) { continue }
        if ($commandLine -match '(?i)^\s*("[^"]*msiexec\.exe"|\S*msiexec\.exe)\s+/V\s*$') { continue }
        $age = 0
        if ($null -ne $process.CreationDate) {
            $age = [int][math]::Max(0, ((Get-Date) - [datetime]$process.CreationDate).TotalMinutes)
        }
        $list += [pscustomobject]@{ ProcessId = [int]$process.ProcessId; AgeMinutes = $age }
    }
    $list
}

try {
    $keyExists = Test-Path -LiteralPath $InProgressKey
    $processes = @(Get-InstallProcess)
    $hung = @($processes | Where-Object { $_.AgeMinutes -ge $HungProcessMinutes })
    $oldest = 0
    if ($processes.Count -gt 0) { $oldest = [int]($processes | Measure-Object -Property AgeMinutes -Maximum).Maximum }

    $summary = 'InProgressKey={0}; InstallProcesses={1}; OldestMinutes={2}; Threshold={3}' -f $keyExists, $processes.Count, $oldest, $HungProcessMinutes

    if ($hung.Count -gt 0) {
        Exit-Script 1 "Drift | $summary; HungProcesses=$($hung.Count); Cause=HungMsiexec"
    }
    if ($keyExists -and $processes.Count -eq 0) {
        Exit-Script 1 "Drift | $summary; Cause=StaleInProgressKey"
    }
    if ($keyExists) {
        Exit-Script 0 "Busy | $summary; Action=Wait"
    }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Detect; HResult=$($_.Exception.HResult)" }
