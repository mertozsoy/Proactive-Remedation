<#
.SYNOPSIS
  Detection script for the Windows startup sound.

.DESCRIPTION
  Reads the startup sound policy value and the device user setting on a Windows client. Exits 1 if the policy value is not set to off, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyKey    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$PolicyValue  = 'DisableStartupSound'
$SettingKey   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation'
$SettingValue = 'DisableStartupSound'

$PackageName = 'StartupSound'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($item.PSObject.Properties.Name -notcontains $Name) { return $null }
    return [int]$item.$Name
}

function Format-RegValue {
    param($Value)
    if ($null -eq $Value) { return 'NotSet' }
    if ($Value -eq 1) { return 'Off' }
    if ($Value -eq 0) { return 'On' }
    return [string]$Value
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | OS=Server' }

    $policy      = Get-RegValue -Path $PolicyKey -Name $PolicyValue
    $setting     = Get-RegValue -Path $SettingKey -Name $SettingValue
    $policyText  = Format-RegValue -Value $policy
    $settingText = Format-RegValue -Value $setting

    if ($policy -eq 0) { Exit-Script 0 "Skipped | Policy=ForcedOn; Setting=$settingText" }
    if ($policy -eq 1) { Exit-Script 0 "Healthy | Policy=$policyText; Setting=$settingText" }
    Exit-Script 1 "Drift | Policy=$policyText; Setting=$settingText"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
