<#
.SYNOPSIS
  Detection script for a leftover TargetReleaseVersion pin that blocks feature updates.

.DESCRIPTION
  Checks the target feature update version under the Windows Update policy key. Exits 1 if a pin is active, is not delivered by MDM and is not in the allowed list, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowedTargetVersions = @()
$PinValueNames         = @('TargetReleaseVersion', 'TargetReleaseVersionInfo', 'ProductVersion')

$PackageName = 'TargetReleaseVersionPin'
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
    $summary = 'Target={0}; Product={1}; Current={2}; MdmManaged={3}' -f ($(if ($state.Target) { $state.Target } else { 'None' })), ($(if ($state.Product) { $state.Product } else { 'None' })), $state.Current, $state.MdmManaged

    if (-not $state.Enabled) { Exit-Script 0 "NotPinned | $summary" }
    if ($state.MdmManaged) { Exit-Script 0 "PolicyManaged | $summary" }
    if ($AllowedTargetVersions -contains $state.Target) { Exit-Script 0 "AllowedPin | $summary" }
    Exit-Script 1 "LeftoverPin | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
