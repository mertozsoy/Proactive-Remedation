<#
.SYNOPSIS
  Detection script for Microsoft Defender SmartScreen that is turned off.

.DESCRIPTION
  Reads the effective App and browser control state. The EnableSmartScreen policy value under HKLM\SOFTWARE\Policies\Microsoft\Windows\System wins over the per-device value in HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer. Also reads the Microsoft Edge SmartScreenEnabled policy. Exits 1 if SmartScreen is off, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SystemPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$EdgePolicyKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$ExplorerKey     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'

$PackageName = 'SmartScreen'
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

function Get-ShellSmartScreen {
    $policyValue = $null
    if (Test-Path -LiteralPath $SystemPolicyKey) {
        $item = Get-ItemProperty -LiteralPath $SystemPolicyKey -ErrorAction Stop
        if ($null -ne $item.EnableSmartScreen) { $policyValue = [int]$item.EnableSmartScreen }
    }

    $uiValue = $null
    if (Test-Path -LiteralPath $ExplorerKey) {
        $item = Get-ItemProperty -LiteralPath $ExplorerKey -ErrorAction Stop
        if ($null -ne $item.SmartScreenEnabled) { $uiValue = [string]$item.SmartScreenEnabled }
    }

    $source = 'Default'
    $on     = $true
    if ($null -ne $policyValue) {
        $source = 'Policy'
        $on     = ($policyValue -ne 0)
    }
    elseif ($null -ne $uiValue) {
        $source = 'DeviceUI'
        $on     = ($uiValue -ne 'Off')
    }

    [pscustomobject]@{ On = $on; Source = $source; PolicyValue = $policyValue; UiValue = $uiValue }
}

function Get-EdgeSmartScreen {
    $edgeValue = $null
    if (Test-Path -LiteralPath $EdgePolicyKey) {
        $item = Get-ItemProperty -LiteralPath $EdgePolicyKey -ErrorAction Stop
        if ($null -ne $item.SmartScreenEnabled) { $edgeValue = [int]$item.SmartScreenEnabled }
    }

    if ($null -eq $edgeValue) {
        return [pscustomobject]@{ On = $true; Source = 'Default'; PolicyValue = $null }
    }
    [pscustomobject]@{ On = ($edgeValue -ne 0); Source = 'Policy'; PolicyValue = $edgeValue }
}

function Format-State {
    param($Shell, $Edge)
    $shellText = 'On'
    if (-not $Shell.On) { $shellText = 'Off(' + $Shell.Source + ')' }
    $edgeText = 'On'
    if (-not $Edge.On) { $edgeText = 'Off(' + $Edge.Source + ')' }
    'Shell=' + $shellText + '; Edge=' + $edgeText
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 ('NotApplicable | ProductType=' + $os.ProductType) }

    $shell = Get-ShellSmartScreen
    $edge  = Get-EdgeSmartScreen
    $text  = Format-State -Shell $shell -Edge $edge

    if (-not $shell.On -or -not $edge.On) { Exit-Script 1 ('Drift | ' + $text) }
    Exit-Script 0 ('Healthy | ' + $text)
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
