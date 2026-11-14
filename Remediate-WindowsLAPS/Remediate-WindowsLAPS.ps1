<#
.SYNOPSIS
  Remediation script for Windows LAPS password backup.

.DESCRIPTION
  Runs LAPS policy processing and, if needed, resets and backs up the password.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'WindowsLAPS'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-LapsPolicy {

    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Policies\LAPS',
                      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS',
                      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\LAPS\Config') {
        $p = Get-ItemProperty $root -ErrorAction SilentlyContinue
        if ($p -and $null -ne $p.BackupDirectory -and $p.BackupDirectory -ne 0) {
            return [pscustomobject]@{
                Source          = $root
                BackupDirectory = [int]$p.BackupDirectory
                PasswordAgeDays = $(if ($p.PasswordAgeDays) { [int]$p.PasswordAgeDays } else { 30 })
            }
        }
    }
    return $null
}

function Get-LastLapsSuccess { param([int]$BackupDirectory)
    $id = if ($BackupDirectory -eq 1) { 10029 } else { 10018 }
    Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-LAPS/Operational'; Id = $id } -MaxEvents 1 -ErrorAction SilentlyContinue
}

try {
    $pol = Get-LapsPolicy
    if (-not $pol) { Exit-Script 0 'No Windows LAPS policy, nothing to do.' }
    $start = Get-Date

    Invoke-LapsPolicyProcessing -ErrorAction Stop
    Start-Sleep -Seconds 15
    $ev = Get-LastLapsSuccess -BackupDirectory $pol.BackupDirectory
    if ($ev -and $ev.TimeCreated -ge $start) { Exit-Script 0 "Policy processed, backup confirmed at $($ev.TimeCreated)" }

    Reset-LapsPassword -ErrorAction Stop
    Start-Sleep -Seconds 15
    $ev = Get-LastLapsSuccess -BackupDirectory $pol.BackupDirectory
    if ($ev -and $ev.TimeCreated -ge $start) { Exit-Script 0 "Password rotated, backup confirmed at $($ev.TimeCreated)" }

    $err = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-LAPS/Operational'; Level = 2; StartTime = $start } -MaxEvents 1 -ErrorAction SilentlyContinue
    $msg = if ($err) { "Event $($err.Id): $(($err.Message -split "`r?`n")[0])" } else { 'No error event logged' }
    Exit-Script 1 "Backup not confirmed. $msg"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
