<#
.SYNOPSIS
  Detection script for Microsoft Defender network protection that is off or in audit mode.

.DESCRIPTION
  Reads the effective network protection state from Get-MpPreference on Windows 10 1709 or later clients. Value 1 is block mode, 2 audit mode and 0 off. The policy registry values are read to show whether Group Policy or Intune owns the setting. Exits 1 when the state is not block mode, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumBuild   = 16299
$ExpectedState  = 1
$ValueName      = 'EnableNetworkProtection'
$PolicyKey      = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection'
$MdmKey         = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager'
$PassiveAvModes = @('Passive', 'SxS Passive Mode')

$PackageName = 'DefenderNetworkProtection'
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

function Get-RegistryState {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    if ($null -eq $item.PSObject.Properties[$Name]) { return $null }
    [int]$item.$Name
}

function Get-ProtectionState {
    $preference = Get-MpPreference -ErrorAction Stop
    $effective  = $null
    if ($null -ne $preference.EnableNetworkProtection) { $effective = [int]$preference.EnableNetworkProtection }

    $policyValue = Get-RegistryState -Path $PolicyKey -Name $ValueName
    $mdmValue    = Get-RegistryState -Path $MdmKey -Name $ValueName

    $source = 'Local'
    if ($null -ne $policyValue) { $source = 'Policy' }
    elseif ($null -ne $mdmValue) { $source = 'MDM' }

    [pscustomobject]@{ Effective = $effective; Source = $source; PolicyValue = $policyValue; MdmValue = $mdmValue }
}

function Format-State {
    param($State)
    $text = 'Off(0)'
    if ($State.Effective -eq 1) { $text = 'Block(1)' }
    elseif ($State.Effective -eq 2) { $text = 'Audit(2)' }
    'State=' + $text + '; Source=' + $State.Source
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt $MinimumBuild) {
        Exit-Script 0 'NotApplicable | Requires=Windows10-1709OrLaterClient'
    }

    $avMode = $null
    try { $avMode = [string](Get-MpComputerStatus -ErrorAction Stop).AMRunningMode } catch { $avMode = $null }
    if ([string]::IsNullOrWhiteSpace($avMode)) { Exit-Script 0 'NotApplicable | DefenderStatusUnavailable' }
    if ($PassiveAvModes -contains $avMode) { Exit-Script 0 ('NotApplicable | AvMode=' + $avMode) }

    $state = $null
    try { $state = Get-ProtectionState } catch { $state = $null }
    if ($null -eq $state -or $null -eq $state.Effective) {
        Exit-Script 0 'NotApplicable | EnableNetworkProtection not reported'
    }

    $text = Format-State -State $state
    if ($state.Effective -ne $ExpectedState) {
        Exit-Script 1 ('Drift | ' + $text + '; Expected=Block(1)')
    }
    Exit-Script 0 ('Healthy | ' + $text)
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
