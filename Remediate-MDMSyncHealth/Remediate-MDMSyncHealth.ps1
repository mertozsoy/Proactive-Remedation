<#
.SYNOPSIS
  Remediation script for Intune MDM sync health.

.DESCRIPTION
  Repairs the sync prerequisites and starts an MDM sync session.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'MDMSyncHealth'
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

try {
    $done = @()
    $enrollId = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -Name ProviderID -ErrorAction SilentlyContinue).ProviderID -eq 'MS DM Server'
    } | Select-Object -First 1 -ExpandProperty PSChildName
    if (-not $enrollId) { Exit-Script 1 'No Intune MDM enrollment found; re-enrollment is required (not automated).' }

    $push = Get-Service -Name dmwappushservice -ErrorAction SilentlyContinue
    if ($push) {
        if ($push.StartType -eq 'Disabled') { Set-Service -Name dmwappushservice -StartupType Manual; $done += 'dmwappush->Manual' }
        if ($push.Status -ne 'Running') { try { Start-Service dmwappushservice -ErrorAction Stop; $done += 'dmwappush started' } catch { Write-IRTLog "dmwappushservice start failed: $_" 'WARN' } }
    }

    $taskPath = "\Microsoft\Windows\EnterpriseMgmt\$enrollId\"
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName 'PushLaunch' -ErrorAction SilentlyContinue
    if (-not $task) { $task = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue | Where-Object TaskName -like 'Schedule #3*' | Select-Object -First 1 }
    if (-not $task) { Exit-Script 1 "No sync task under $taskPath. $($done -join '; ')" }

    if ($task.State -eq 'Disabled') { Enable-ScheduledTask -InputObject $task | Out-Null; $done += "$($task.TaskName) enabled" }
    Start-ScheduledTask -InputObject $task -ErrorAction Stop
    $done += "$($task.TaskName) started"

    Exit-Script 0 ($done -join '; ')
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
