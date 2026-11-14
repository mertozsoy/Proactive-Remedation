<#
.SYNOPSIS
  Detection script for the Secure Boot 2023 certificate update.

.DESCRIPTION
  Checks whether the device has moved to the 2023 Secure Boot certificates. Exits 1 if the update has not started or completed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'SecureBootCA2023'
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

try {
    try { $sbOn = Confirm-SecureBootUEFI -ErrorAction Stop }
    catch { Exit-Script 0 'NotApplicable: legacy BIOS or Secure Boot state unreadable' }
    if (-not $sbOn) { Exit-Script 0 'NotApplicable: Secure Boot is disabled' }

    $sbKey   = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
    $svcKey  = Join-Path $sbKey 'Servicing'
    $status  = (Get-ItemProperty -Path $svcKey -Name UEFICA2023Status -ErrorAction SilentlyContinue).UEFICA2023Status
    if (-not $status) { $status = (Get-ItemProperty -Path $sbKey -Name UEFICA2023Status -ErrorAction SilentlyContinue).UEFICA2023Status }
    $errVal  = (Get-ItemProperty -Path $svcKey -Name UEFICA2023Error -ErrorAction SilentlyContinue).UEFICA2023Error
    $avail   = (Get-ItemProperty -Path $sbKey -Name AvailableUpdates -ErrorAction SilentlyContinue).AvailableUpdates

    $dbHas2023 = $false
    try { $dbHas2023 = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db -ErrorAction Stop).bytes) -match 'Windows UEFI CA 2023' } catch { }

    $task      = Get-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction SilentlyContinue
    $taskState = if ($task) { [string]$task.State } else { 'Missing' }

    $summary = 'Status={0}; DB2023={1}; AvailableUpdates=0x{2:X}; Error={3}; Task={4}' -f `
        ($(if ($status) { $status } else { 'NotSet' })), $dbHas2023, [int]$avail, ($(if ($errVal) { $errVal } else { 'None' })), $taskState

    if ($status -eq 'Updated') { Exit-Script 0 "Compliant | $summary" }
    Exit-Script 1 "NonCompliant | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
