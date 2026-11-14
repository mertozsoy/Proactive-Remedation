<#
.SYNOPSIS
  Remediation script for a leftover TargetReleaseVersion pin that blocks feature updates.

.DESCRIPTION
  Removes TargetReleaseVersion, TargetReleaseVersionInfo and ProductVersion from the Windows Update policy key when the pin is not delivered by MDM and not in the allowed list. Exits 0 when the values are gone, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowedTargetVersions = @()
$PinValueNames         = @('TargetReleaseVersion', 'TargetReleaseVersionInfo', 'ProductVersion')

$PackageName = 'TargetReleaseVersionPin'
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

$WuPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$MdmKey      = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'

function Get-PinState {
    $wu  = Get-ItemProperty -LiteralPath $WuPolicyKey -ErrorAction SilentlyContinue
    $mdm = Get-ItemProperty -LiteralPath $MdmKey -ErrorAction SilentlyContinue
    $cv  = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Enabled    = ($wu.TargetReleaseVersion -eq 1)
        Target     = [string]$wu.TargetReleaseVersionInfo
        Product    = [string]$wu.ProductVersion
        Present    = @($PinValueNames | Where-Object { $null -ne $wu.$_ })
        MdmManaged = ($null -ne $mdm.TargetReleaseVersion -or $null -ne $mdm.ProductVersion)
        Current    = [string]$cv.DisplayVersion
    }
}

try {
    $state = Get-PinState
    if (-not $state.Enabled) { Exit-Script 0 'NoAction | Target=None' }
    if ($state.MdmManaged) { Exit-Script 1 "Skipped | Reason=MdmManaged; Target=$($state.Target)" }
    if ($AllowedTargetVersions -contains $state.Target) { Exit-Script 0 "NoAction | Reason=AllowedPin; Target=$($state.Target)" }

    foreach ($name in $state.Present) {
        Remove-ItemProperty -LiteralPath $WuPolicyKey -Name $name -Force -ErrorAction Stop
        Write-IRTLog "Removed policy value: $name"
    }

    $restarted = $false
    $svc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        try { Restart-Service -Name wuauserv -Force -ErrorAction Stop; $restarted = $true }
        catch { Write-IRTLog "Restart-Service wuauserv: $($_.Exception.Message)" 'WARN' }
    }

    $after = Get-PinState
    $summary = 'Removed={0}; OldTarget={1}; OldProduct={2}; WuRestarted={3}' -f ($state.Present -join ','), $state.Target, ($(if ($state.Product) { $state.Product } else { 'None' })), $restarted
    if ($after.Present.Count -gt 0) { Exit-Script 1 "Failed (StillSet=$($after.Present -join ',')) | $summary" }
    Exit-Script 0 "Remediated | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
