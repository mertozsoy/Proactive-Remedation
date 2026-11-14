<#
.SYNOPSIS
  Detection script for Windows LAPS password backup.

.DESCRIPTION
  Checks the last LAPS password backup time. Exits 1 if the password was not backed up within the threshold.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$GraceDays = 2

$PackageName = 'WindowsLAPS'
$Phase       = 'Detect'
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
    if (-not $pol) { Exit-Script 0 'NotApplicable | No Windows LAPS policy found' }
    $dir = if ($pol.BackupDirectory -eq 1) { 'EntraID' } else { 'AD' }

    $ev = Get-LastLapsSuccess -BackupDirectory $pol.BackupDirectory
    if (-not $ev) { Exit-Script 1 "NoSuccessEvent | Directory=$dir; AgeDays=$($pol.PasswordAgeDays)" }

    $ageDays = [math]::Round(((Get-Date) - $ev.TimeCreated).TotalDays, 1)
    $summary = 'Directory={0}; LastBackup={1:yyyy-MM-dd HH:mm}; DaysAgo={2}; PolicyAgeDays={3}' -f $dir, $ev.TimeCreated, $ageDays, $pol.PasswordAgeDays
    if ($ageDays -gt ($pol.PasswordAgeDays + $GraceDays)) { Exit-Script 1 "Overdue | $summary" }
    Exit-Script 0 "OK | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
