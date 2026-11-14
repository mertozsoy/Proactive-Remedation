<#
.SYNOPSIS
  Remediation script for the Secure Boot 2023 certificate update.

.DESCRIPTION
  Starts the Windows driven Secure Boot certificate update and runs the Secure-Boot-Update task.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'SecureBootCA2023'
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

$TargetMask = 0x5944

try {
    $sbKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
    $svcKey = Join-Path $sbKey 'Servicing'

    $errVal = (Get-ItemProperty -Path $svcKey -Name UEFICA2023Error -ErrorAction SilentlyContinue).UEFICA2023Error
    if ($errVal) {
        Exit-Script 1 "Stopped: UEFICA2023Error=$errVal. Check System log events 1795/1796/1801/1803 and update OEM firmware first."
    }

    $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction SilentlyContinue
    if (-not $task) { Exit-Script 1 'Secure-Boot-Update task missing. Install the latest cumulative update first.' }
    if ($task.State -eq 'Disabled') {
        Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        Write-IRTLog 'Secure-Boot-Update task was disabled, enabled it.' 'WARN'
    }

    $avail = [int](Get-ItemProperty -Path $sbKey -Name AvailableUpdates -ErrorAction SilentlyContinue).AvailableUpdates
    if ($avail -eq 0) {
        Set-ItemProperty -Path $sbKey -Name AvailableUpdates -Value $TargetMask -Type DWord -ErrorAction Stop
        Write-IRTLog ('AvailableUpdates set to 0x{0:X}' -f $TargetMask)
        $action = 'Queued 0x5944'
    }
    else {
        $action = 'Already queued (0x{0:X}), not overwritten' -f $avail
        Write-IRTLog $action
    }

    Start-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction Stop
    Start-Sleep -Seconds 20
    $after = [int](Get-ItemProperty -Path $sbKey -Name AvailableUpdates -ErrorAction SilentlyContinue).AvailableUpdates

    Exit-Script 0 ('{0}; task started; AvailableUpdates now 0x{1:X}. Restart required (may need 2).' -f $action, $after)
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
