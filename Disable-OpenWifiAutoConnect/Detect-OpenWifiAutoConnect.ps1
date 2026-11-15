<#
.SYNOPSIS
  Detection script for unsecured Wi-Fi profiles that still join automatically.

.DESCRIPTION
  Reads the machine WLAN profile store and lists profiles with open authentication and no encryption that have connectionMode set to auto. Optional check of the hotspot auto-connect policy value. Exits 1 if a profile or value is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$KeepProfileNames          = @()
$DisableHotspotAutoConnect = $false
$MaxNamesInOutput          = 5

$PackageName = 'OpenWifiAutoConnect'
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

$ProfileStore = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces'
$ProfileRoot  = "/*[local-name()='WLANProfile']"
$SecurityPath = "$ProfileRoot/*[local-name()='MSM']/*[local-name()='security']/*[local-name()='authEncryption']"
$HotspotKey   = 'HKLM:\SOFTWARE\Microsoft\wcmsvc\wifinetworkmanager\config'
$HotspotValue = 'AutoConnectAllowedOEM'

function Get-NodeText {
    param($Xml, [string]$Path)
    $node = $Xml.SelectSingleNode($Path)
    if ($null -eq $node) { return '' }
    return $node.InnerText
}

function Format-NameList {
    param([string[]]$Names)
    $unique = @($Names | Sort-Object -Unique)
    $listed = @($unique | Select-Object -First $MaxNamesInOutput) -join ','
    if ($unique.Count -gt $MaxNamesInOutput) {
        $listed = '{0} (+{1} more)' -f $listed, ($unique.Count - $MaxNamesInOutput)
    }
    return $listed
}

function Get-WlanProfileState {
    $state = [pscustomobject]@{ Total = 0; OpenAuto = @() }
    if (-not (Test-Path -LiteralPath $ProfileStore)) { return $state }
    foreach ($interfaceDir in @(Get-ChildItem -LiteralPath $ProfileStore -Directory -ErrorAction SilentlyContinue)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $interfaceDir.FullName -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
            try {
                $xml = [xml](Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop)
            }
            catch {
                Write-IRTLog "Profile XML could not be read: $($file.FullName)" 'WARN'
                continue
            }
            $name = Get-NodeText -Xml $xml -Path "$ProfileRoot/*[local-name()='name']"
            if (-not $name) { continue }
            $state.Total = $state.Total + 1
            if ($KeepProfileNames -contains $name) { continue }
            if ($null -ne $xml.SelectSingleNode("$ProfileRoot/*[local-name()='Hotspot2']")) { continue }
            $authentication = Get-NodeText -Xml $xml -Path "$SecurityPath/*[local-name()='authentication']"
            $encryption     = Get-NodeText -Xml $xml -Path "$SecurityPath/*[local-name()='encryption']"
            if ($authentication -ne 'open' -or $encryption -ne 'none') { continue }
            $connectionMode = Get-NodeText -Xml $xml -Path "$ProfileRoot/*[local-name()='connectionMode']"
            if (-not $connectionMode) { $connectionMode = 'auto' }
            if ($connectionMode -ne 'auto') { continue }
            $state.OpenAuto += [pscustomobject]@{
                Name = $name
                File = $file.FullName
            }
        }
    }
    return $state
}

function Get-HotspotAutoConnectValue {
    if (-not (Test-Path -LiteralPath $HotspotKey)) { return 1 }
    $value = (Get-ItemProperty -LiteralPath $HotspotKey -Name $HotspotValue -ErrorAction SilentlyContinue).$HotspotValue
    if ($null -eq $value) { return 1 }
    return [int]$value
}

try {
    if (-not (Test-Path -LiteralPath $ProfileStore)) { Exit-Script 0 'NotApplicable | WLAN profile store not found' }

    $state   = Get-WlanProfileState
    $hotspot = Get-HotspotAutoConnectValue
    $drift   = @($state.OpenAuto)

    $hotspotDrift = $false
    if ($DisableHotspotAutoConnect -and $hotspot -ne 0) { $hotspotDrift = $true }

    if ($drift.Count -eq 0 -and -not $hotspotDrift) {
        Exit-Script 0 "Healthy | Profiles=$($state.Total); OpenAuto=0; HotspotAutoConnect=$hotspot"
    }

    $names   = Format-NameList -Names @($drift | ForEach-Object { $_.Name })
    $summary = "Drift | Profiles=$($state.Total); OpenAuto=$($drift.Count)"
    if ($drift.Count -gt 0) { $summary = "$summary; Names=$names" }
    if ($hotspotDrift) { $summary = "$summary; HotspotAutoConnect=$hotspot" }
    Exit-Script 1 $summary
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
