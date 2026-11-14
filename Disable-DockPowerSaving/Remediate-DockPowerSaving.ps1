<#
.SYNOPSIS
  Remediation script that turns off PCI Express link state power management and USB selective suspend.

.DESCRIPTION
  Sets both power settings to Off in the active power scheme with powercfg and reloads the scheme.
  Exits 0 after verification, 1 on failure or when changes are disabled.

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
$ApplyChanges     = $true

$PowerSchemesKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$PowerSettingsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
$PowerCfg        = Join-Path $env:SystemRoot 'System32\powercfg.exe'
$Sources         = @('AC')
if ($CheckOnBattery) { $Sources = @('AC', 'DC') }

$PackageName = 'DockPowerSaving'
$Phase       = 'Remediate'
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

function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $process = Start-Process -FilePath $PowerCfg -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -ne 0) {
        throw ('powercfg {0} failed with exit code {1}' -f $Arguments[0], $process.ExitCode)
    }
}

try {
    if (-not (Test-Path -LiteralPath $PowerSchemesKey -ErrorAction Stop)) {
        Exit-Script 0 'NotApplicable | PowerSchemes=Absent'
    }
    if (-not (Test-Path -LiteralPath $PowerCfg -ErrorAction Stop)) {
        Exit-Script 0 'NotApplicable | PowerCfg=Absent'
    }
    $activeScheme = (Get-ItemProperty -LiteralPath $PowerSchemesKey -Name ActivePowerScheme -ErrorAction Stop).ActivePowerScheme
    if (-not $activeScheme) { Exit-Script 0 'NotApplicable | ActivePowerScheme=Empty' }

    $states    = @(Get-PowerStateList -Scheme $activeScheme)
    $summary   = Format-PowerState -States $states
    $supported = @($states | Where-Object { $_.State -ne 'Unsupported' })
    $drift     = @($supported | Where-Object { $_.State -ne 'Off' })
    if ($supported.Count -eq 0) { Exit-Script 0 "NotApplicable | $summary" }
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    if (-not $ApplyChanges) { Exit-Script 1 "ReportOnly | $summary; ApplyChanges=False" }

    $changed = 0
    foreach ($item in $drift) {
        $valueSwitch = '/setacvalueindex'
        if ($item.Source -eq 'DC') { $valueSwitch = '/setdcvalueindex' }
        Invoke-PowerCfg -Arguments @($valueSwitch, 'SCHEME_CURRENT', $item.SubGroup, $item.Setting, [string]$ExpectedIndex)
        $changed++
        Write-IRTLog ('Set {0}({1})={2} via {3}' -f $item.Name, $item.Source, $ExpectedIndex, $valueSwitch)
    }
    Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_CURRENT')

    $after        = @(Get-PowerStateList -Scheme $activeScheme)
    $afterSummary = Format-PowerState -States $after
    if (@($after | Where-Object { $_.State -notin @('Off', 'Unsupported') }).Count -gt 0) {
        Exit-Script 1 "Failed | $afterSummary; Changed=$changed"
    }
    Exit-Script 0 "Fixed | $afterSummary; Changed=$changed; Apply=SetActiveScheme"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
