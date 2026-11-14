<#
.SYNOPSIS
  Detection script for Windows Update policy values that block Microsoft Store and Company Portal installs.

.DESCRIPTION
  Checks DoNotConnectToWindowsUpdateInternetLocations and DisableWindowsUpdateAccess under the Windows Update policy key. Exits 1 if a blocking value is set on a device that does not use WSUS, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BlockingValues          = @('DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess')
$RemoveWhenWsusConfigured = $false

$PackageName = 'WUInternetLocationBlock'
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

function Get-BlockState {
    $wu = Get-ItemProperty -LiteralPath $WuPolicyKey -ErrorAction SilentlyContinue
    $au = Get-ItemProperty -LiteralPath (Join-Path $WuPolicyKey 'AU') -ErrorAction SilentlyContinue
    $mdm = Get-ItemProperty -LiteralPath $MdmKey -ErrorAction SilentlyContinue
    $active = @($BlockingValues | Where-Object { $wu.$_ -eq 1 })
    [pscustomobject]@{
        Active     = $active
        MdmManaged = @($active | Where-Object { $null -ne $mdm.$_ })
        WsusInUse  = ($au.UseWUServer -eq 1 -and -not [string]::IsNullOrWhiteSpace($wu.WUServer))
    }
}

try {
    $state = Get-BlockState
    $summary = 'Blocking={0}; WsusInUse={1}; MdmManaged={2}' -f ($(if ($state.Active.Count) { $state.Active -join ',' } else { 'None' })), $state.WsusInUse, ($state.MdmManaged.Count -gt 0)

    if ($state.Active.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    if ($state.MdmManaged.Count -gt 0) { Exit-Script 0 "PolicyManaged | $summary" }
    if ($state.WsusInUse -and -not $RemoveWhenWsusConfigured) { Exit-Script 0 "WsusInUse | $summary" }
    Exit-Script 1 "Blocked | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
