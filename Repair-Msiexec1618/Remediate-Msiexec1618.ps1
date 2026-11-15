<#
.SYNOPSIS
  Remediation script that clears a hung msiexec process and a stale Windows Installer InProgress key.

.DESCRIPTION
  Ends msiexec processes that have run past $HungProcessMinutes, waits for them to exit, then removes the InProgress key after a reg export backup.
  A live installation younger than the threshold is left alone.
  Exits 0 when the installer state is clear, 1 when a process or the key is still present.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$HungProcessMinutes      = 90
$TerminateHungMsiexec    = $false
$RemoveStaleInProgressKey = $true
$WaitSeconds             = 30
$InProgressKey           = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress'
$BackupRoot              = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'Msiexec1618'
$Phase       = 'Remediate'
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

function Save-InProgressBackup {
    $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    $file = Join-Path $BackupRoot ('InstallerInProgress-{0}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $output = & reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress' $file /y 2>&1
    if ($LASTEXITCODE -ne 0) { throw "reg export failed with exit code $LASTEXITCODE ($($output -join ' '))" }
    $file
}

try {
    $keyExists = Test-Path -LiteralPath $InProgressKey
    $processes = @(Get-InstallProcess)
    $hung = @($processes | Where-Object { $_.AgeMinutes -ge $HungProcessMinutes })
    $oldest = 0
    if ($processes.Count -gt 0) { $oldest = [int]($processes | Measure-Object -Property AgeMinutes -Maximum).Maximum }
    $summary = 'InProgressKey={0}; OldestMinutes={1}; Threshold={2}' -f $keyExists, $oldest, $HungProcessMinutes

    if ($processes.Count -eq 0 -and -not $keyExists) {
        Exit-Script 0 "Healthy | $summary"
    }
    if ($hung.Count -eq 0 -and $keyExists -and $processes.Count -gt 0) {
        Exit-Script 0 "Busy | $summary; InstallProcesses=$($processes.Count); Action=Wait"
    }
    if ($hung.Count -gt 0 -and -not $TerminateHungMsiexec) {
        Exit-Script 1 "Failed | $summary; HungProcesses=$($hung.Count); Toggle=TerminateHungMsiexec"
    }
    if (-not $RemoveStaleInProgressKey -and $keyExists) {
        Exit-Script 0 "ReportOnly | $summary; InstallProcesses=$($processes.Count); Toggle=RemoveStaleInProgressKey"
    }

    $terminated = 0
    if ($hung.Count -gt 0) {
        foreach ($item in $hung) {
            $process = Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
            if ($null -eq $process) { continue }
            Stop-Process -Id $item.ProcessId -Force -ErrorAction Stop
            Write-IRTLog "msiexec ended: pid=$($item.ProcessId) age=$($item.AgeMinutes) minutes"
            $terminated++
        }

        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        do {
            Start-Sleep -Seconds 2
            $remaining = @(Get-InstallProcess)
        } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)

        if ($remaining.Count -gt 0) {
            $ids = ($remaining | Select-Object -ExpandProperty ProcessId) -join ','
            Exit-Script 1 "Failed | $summary; Terminated=$terminated; RemainingProcesses=$($remaining.Count); Pids=$ids"
        }
    }

    $keyRemoved = $false
    $backupFile = ''
    if (Test-Path -LiteralPath $InProgressKey) {
        $backupFile = Save-InProgressBackup
        Remove-Item -LiteralPath $InProgressKey -Recurse -Force -ErrorAction Stop
        Write-IRTLog "InProgress key removed, backup: $backupFile"
        $keyRemoved = $true
    }

    $keyLeft = Test-Path -LiteralPath $InProgressKey
    $processesLeft = @(Get-InstallProcess)
    $result = 'Terminated={0}; KeyRemoved={1}; InstallProcesses={2}; Threshold={3}' -f $terminated, $keyRemoved, $processesLeft.Count, $HungProcessMinutes
    if ($backupFile) { $result = $result + "; Backup=$backupFile" }

    if ($keyLeft -or $processesLeft.Count -gt 0) {
        Exit-Script 1 "Failed | $result; InProgressKey=$keyLeft"
    }
    Exit-Script 0 "Fixed | $result"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
