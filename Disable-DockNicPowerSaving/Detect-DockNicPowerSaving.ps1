<#
.SYNOPSIS
  Detection script for NIC power saving on dock and USB-C Ethernet adapters.

.DESCRIPTION
  Finds physical Ethernet adapters that sit on the USB bus or carry a dock description. Reads AllowComputerToTurnOffDevice and the Energy Efficient Ethernet keywords of each adapter. Exits 1 if power saving is enabled on any adapter in scope, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AdapterScope                   = 'DockAndUsb'
$DockNamePattern                = 'USB|Dock|Thunderbolt|Type-C'
$DisableEnergyEfficientEthernet = $true
$EnergyEfficientKeywords        = @('*EEE', 'AdvancedEEE', 'EnableGreenEthernet', 'GigaLite', 'GreenEthernet')

$PackageName = 'DockNicPowerSaving'
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

function Get-SettingState {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = [string]$Value
    if ($text -in @('Enabled', '1', 'True')) { return $true }
    if ($text -in @('Disabled', '0', 'False')) { return $false }
    $null
}

function Get-AdapterState {
    $cimAdapters = @(Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop | Where-Object {
        $_.PhysicalAdapter -eq $true -and [string]$_.AdapterTypeId -eq '0' -and [int]$_.InterfaceIndex -gt 0
    })
    $states = @()
    foreach ($netAdapter in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
        $cim = $cimAdapters | Where-Object { $_.InterfaceIndex -eq $netAdapter.ifIndex } | Select-Object -First 1
        if ($null -eq $cim) { continue }
        $pnpId  = [string]$cim.PNPDeviceID
        $isUsb  = $pnpId.StartsWith('USB\')
        $isDock = ([string]$netAdapter.InterfaceDescription -match $DockNamePattern) -or ($pnpId -match $DockNamePattern)
        if ($AdapterScope -eq 'DockAndUsb' -and -not ($isUsb -or $isDock)) { continue }

        $powerSave = $null
        try {
            $powerManagement = Get-NetAdapterPowerManagement -Name $netAdapter.Name -ErrorAction Stop
            $powerSave = Get-SettingState -Value $powerManagement.AllowComputerToTurnOffDevice
        } catch { $powerSave = $null }

        $enabledKeywords = @()
        if ($DisableEnergyEfficientEthernet) {
            try { $advanced = @(Get-NetAdapterAdvancedProperty -Name $netAdapter.Name -ErrorAction Stop) } catch { $advanced = @() }
            foreach ($keyword in $EnergyEfficientKeywords) {
                $property = $advanced | Where-Object { $_.RegistryKeyword -eq $keyword } | Select-Object -First 1
                if ($null -eq $property) { continue }
                if ([string]$property.RegistryValue -eq '1') { $enabledKeywords += $keyword }
            }
        }

        $bus = 'PCI'
        if ($isUsb) { $bus = 'USB' } elseif ($isDock) { $bus = 'Dock' }

        $states += [pscustomobject]@{
            Name        = [string]$netAdapter.Name
            Description = [string]$netAdapter.InterfaceDescription
            Bus         = $bus
            PowerSave   = $powerSave
            EeeKeywords = $enabledKeywords
        }
    }
    $states
}

try {
    if ($AdapterScope -notin @('DockAndUsb', 'All')) { Exit-Script 1 'Error | Invalid AdapterScope' }

    $states = @(Get-AdapterState)
    if ($states.Count -eq 0) { Exit-Script 0 "NotApplicable | Scope=$AdapterScope; Adapters=0" }

    $powerSaveCount = @($states | Where-Object { $_.PowerSave -eq $true }).Count
    $eeeCount       = @($states | Where-Object { $_.EeeKeywords.Count -gt 0 }).Count
    foreach ($state in $states) {
        Write-IRTLog ('Adapter={0}; Bus={1}; PowerSave={2}; Eee={3}' -f $state.Description, $state.Bus, $state.PowerSave, ($state.EeeKeywords -join '/'))
    }

    $summary = 'Scope={0}; Adapters={1}; PowerSave={2}; Eee={3}' -f $AdapterScope, $states.Count, $powerSaveCount, $eeeCount
    if ($powerSaveCount -gt 0 -or $eeeCount -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
