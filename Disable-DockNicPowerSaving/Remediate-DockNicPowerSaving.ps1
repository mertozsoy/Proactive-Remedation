<#
.SYNOPSIS
  Remediation script that turns off power saving on dock and USB-C Ethernet adapters.

.DESCRIPTION
  Disables NIC power management on dock and USB Ethernet adapters and sets Energy Efficient Ethernet keywords to 0 when the driver exposes them. The adapter is not restarted. Exits 0 when power saving is gone from every adapter in scope, 1 otherwise.

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

    $initial = @(Get-AdapterState)
    if ($initial.Count -eq 0) { Exit-Script 0 "NotApplicable | Scope=$AdapterScope; Adapters=0" }

    $powerFixed = 0
    $eeeFixed   = 0
    foreach ($state in $initial) {
        try {
            if ($state.PowerSave -eq $true) {
                Disable-NetAdapterPowerManagement -Name $state.Name -NoRestart -ErrorAction Stop
                $powerFixed++
                Write-IRTLog "Power management disabled on $($state.Description)"
            }
            foreach ($keyword in $state.EeeKeywords) {
                Set-NetAdapterAdvancedProperty -Name $state.Name -RegistryKeyword $keyword -RegistryValue '0' -NoRestart -ErrorAction Stop
                $eeeFixed++
                Write-IRTLog "Energy Efficient Ethernet disabled on $($state.Description); Keyword=$keyword"
            }
        } catch {
            Write-IRTLog "Adapter update failed: $($state.Description); Detail=$($_.Exception.Message)" 'WARN'
        }
    }

    $final      = @(Get-AdapterState)
    $powerLeft  = @($final | Where-Object { $_.PowerSave -eq $true }).Count
    $eeeLeft    = @($final | Where-Object { $_.EeeKeywords.Count -gt 0 }).Count
    $summary    = 'Scope={0}; Adapters={1}; PowerSaveFixed={2}; EeeFixed={3}' -f $AdapterScope, $final.Count, $powerFixed, $eeeFixed

    if ($powerLeft -gt 0 -or $eeeLeft -gt 0) {
        Exit-Script 1 "Failed | $summary; PowerSaveLeft=$powerLeft; EeeLeft=$eeeLeft"
    }
    if ($powerFixed -eq 0 -and $eeeFixed -eq 0) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
