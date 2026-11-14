<#
.SYNOPSIS
  Detection script for PCI Express link state power management and USB selective suspend.

.DESCRIPTION
  Reads the active power scheme and checks whether PCI Express link state power management and USB selective suspend are turned off.
  Exits 1 if a setting is enabled or not set, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PcieSubGroupGuid = '501a4d13-42af-4429-9fd1-a8218c268e20'
$PcieSettingGuid  = 'ee12f906-d277-404b-b6da-e5fa1a576df5'
$UsbSubGroupGuid  = '2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSettingGuid   = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$ExpectedIndex    = 0
$CheckOnBattery   = $false

$PowerSchemesKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$PowerSettingsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
$Sources         = @('AC')
if ($CheckOnBattery) { $Sources = @('AC', 'DC') }

$PackageName = 'DockPowerSaving'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $logDirectory = Split-Path -Path $LogFile -Parent
        if (-not (Test-Path -LiteralPath $logDirectory -ErrorAction Stop)) {
            New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
        }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { return }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-PowerSettingState {
    param([string]$Name, [string]$SubGroup, [string]$Setting, [string]$Source, [string]$Scheme)
    $valueName = 'ACSettingIndex'
    if ($Source -eq 'DC') { $valueName = 'DCSettingIndex' }
    $definitionPath = '{0}\{1}\{2}' -f $PowerSettingsKey, $SubGroup, $Setting
    $path = '{0}\{1}\{2}\{3}' -f $PowerSchemesKey, $Scheme, $SubGroup, $Setting
    $state = [pscustomobject]@{
        Name     = $Name
        SubGroup = $SubGroup
        Setting  = $Setting
        Source   = $Source
        State    = 'NotSet'
        Index    = $null
    }
    if (-not (Test-Path -LiteralPath $definitionPath -ErrorAction Stop)) {
        $state.State = 'Unsupported'
        return $state
    }
    if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { return $state }
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    try {
        if ($key.GetValueNames() -notcontains $valueName) { return $state }
        if ($key.GetValueKind($valueName) -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
            $state.State = 'WrongType'
            return $state
        }
        $state.Index = [int]$key.GetValue($valueName)
        if ($state.Index -eq $ExpectedIndex) { $state.State = 'Off' }
        else { $state.State = 'Enabled' }
    }
    finally { $key.Close() }
    return $state
}

function Get-PowerStateList {
    param([string]$Scheme)
    $list = @()
    foreach ($source in $Sources) {
        $list += Get-PowerSettingState -Name 'PcieAspm' -SubGroup $PcieSubGroupGuid -Setting $PcieSettingGuid -Source $source -Scheme $Scheme
        $list += Get-PowerSettingState -Name 'UsbSelectiveSuspend' -SubGroup $UsbSubGroupGuid -Setting $UsbSettingGuid -Source $source -Scheme $Scheme
    }
    $list
}

function Format-PowerState {
    param([object[]]$States)
    (@($States | ForEach-Object {
        if ($null -eq $_.Index) { '{0}({1})={2}' -f $_.Name, $_.Source, $_.State }
        else { '{0}({1})={2}' -f $_.Name, $_.Source, $_.Index }
    }) -join '; ')
}

try {
    if (-not (Test-Path -LiteralPath $PowerSchemesKey -ErrorAction Stop)) {
        Exit-Script 0 'NotApplicable | PowerSchemes=Absent'
    }
    $activeScheme = (Get-ItemProperty -LiteralPath $PowerSchemesKey -Name ActivePowerScheme -ErrorAction Stop).ActivePowerScheme
    if (-not $activeScheme) { Exit-Script 0 'NotApplicable | ActivePowerScheme=Empty' }

    $states  = @(Get-PowerStateList -Scheme $activeScheme)
    $summary = Format-PowerState -States $states
    $supported = @($states | Where-Object { $_.State -ne 'Unsupported' })

    if ($supported.Count -eq 0) { Exit-Script 0 "NotApplicable | $summary" }
    if (@($supported | Where-Object { $_.State -ne 'Off' }).Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
