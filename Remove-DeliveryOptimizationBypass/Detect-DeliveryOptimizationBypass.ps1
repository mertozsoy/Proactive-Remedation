<#
.SYNOPSIS
  Detection script for a leftover Delivery Optimization download mode.

.DESCRIPTION
  Reads the DownloadMode policy value under the Delivery Optimization policy key. Exits 1 when the value is 99 (Simple) or 100 (Bypass), 0 when it is absent or set to a supported mode.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DriftModes             = @(99, 100)
$TreatSimpleModeAsDrift = $true

$PackageName = 'DeliveryOptimizationBypass'
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

$DoPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
$MdmKey      = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization'

function Get-DoState {
    $policy = Get-ItemProperty -LiteralPath $DoPolicyKey -ErrorAction SilentlyContinue
    $mdm    = Get-ItemProperty -LiteralPath $MdmKey -ErrorAction SilentlyContinue
    $mode   = $null
    if ($null -ne $policy -and $null -ne $policy.DownloadMode) { $mode = [int]$policy.DownloadMode }
    $managed = $false
    if ($null -ne $mdm -and $null -ne $mdm.DODownloadMode) { $managed = $true }
    [pscustomobject]@{ Mode = $mode; MdmManaged = $managed }
}

try {
    $state = Get-DoState
    if ($null -eq $state.Mode) { Exit-Script 0 'Healthy | DownloadMode=NotSet' }
    if ($DriftModes -notcontains $state.Mode) { Exit-Script 0 "Healthy | DownloadMode=$($state.Mode)" }
    if ($state.Mode -eq 99 -and -not $TreatSimpleModeAsDrift) { Exit-Script 0 'Healthy | DownloadMode=99; Simple=Allowed' }

    $source = 'Local'
    if ($state.MdmManaged) { $source = 'MDM' }
    Exit-Script 1 "Drift | DownloadMode=$($state.Mode); Source=$source"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
