<#
.SYNOPSIS
  Remediation script for Intune Management Extension health.

.DESCRIPTION
  Sets the IME service to Automatic and restarts it two minutes later through a one time scheduled task, so the result reaches Intune first.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'IMEHealth'
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

$TaskName = 'IRT-Restart-IME'

try {
    Set-Service -Name IntuneManagementExtension -StartupType Automatic -ErrorAction Stop

    $cmd     = 'Restart-Service -Name IntuneManagementExtension -Force; Start-Sleep 5; Unregister-ScheduledTask -TaskName ' + $TaskName + ' -Confirm:$false'
    $action  = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
                   -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$cmd`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2)
    $trigger.EndBoundary = (Get-Date).AddMinutes(30).ToString('s')
    $princ   = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 5) -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $princ -Settings $set -Force -ErrorAction Stop | Out-Null
    Exit-Script 0 "StartType set to Automatic; IME restart scheduled via task '$TaskName' in 2 minutes."
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
