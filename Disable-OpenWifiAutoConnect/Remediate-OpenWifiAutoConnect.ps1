<#
.SYNOPSIS
  Remediation script that stops unsecured Wi-Fi profiles from joining automatically.

.DESCRIPTION
  Sets connectionMode to manual with netsh for every profile that has open authentication and no encryption. Optionally turns off the hotspot auto-connect policy value. Re-reads the profile store and exits 0 when no open profile is left on auto, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation         = $true
$KeepProfileNames          = @()
$DisableHotspotAutoConnect = $false
$MaxNamesInOutput          = 5

$PackageName = 'OpenWifiAutoConnect'
$Phase       = 'Remediate'
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

    $state        = Get-WlanProfileState
    $hotspot      = Get-HotspotAutoConnectValue
    $drift        = @($state.OpenAuto)
    $hotspotDrift = $false
    if ($DisableHotspotAutoConnect -and $hotspot -ne 0) { $hotspotDrift = $true }

    if ($drift.Count -eq 0 -and -not $hotspotDrift) {
        Exit-Script 0 "Healthy | Profiles=$($state.Total); OpenAuto=0; HotspotAutoConnect=$hotspot"
    }

    if (-not $EnableRemediation) {
        $reportNames = Format-NameList -Names @($drift | ForEach-Object { $_.Name })
        Exit-Script 1 "ReportOnly | OpenAuto=$($drift.Count); Names=$reportNames; EnableRemediation=false"
    }

    $changed = 0
    $failed  = 0
    foreach ($openProfile in $drift) {
        $null = & netsh.exe wlan set profileparameter "name=$($openProfile.Name)" connectionmode=manual 2>&1
        $code = $LASTEXITCODE
        Write-IRTLog "netsh set profileparameter connectionmode=manual for $($openProfile.Name) exit code $code"
        if ($code -eq 0) { $changed++ } else { $failed++ }
    }

    if ($hotspotDrift) {
        if (-not (Test-Path -LiteralPath $HotspotKey)) {
            $null = New-Item -Path $HotspotKey -Force -ErrorAction SilentlyContinue
        }
        $null = New-ItemProperty -LiteralPath $HotspotKey -Name $HotspotValue -Value 0 -PropertyType DWord -Force
        Write-IRTLog "Hotspot auto connect value set to 0"
    }

    $remaining = $null
    for ($i = 0; $i -lt 5; $i++) {
        $remaining    = Get-WlanProfileState
        $left         = @($remaining.OpenAuto)
        $leftHotspot  = $false
        if ($DisableHotspotAutoConnect -and ((Get-HotspotAutoConnectValue) -ne 0)) { $leftHotspot = $true }
        if ($left.Count -eq 0 -and -not $leftHotspot) { break }
        Start-Sleep -Seconds 1
    }

    $left      = @($remaining.OpenAuto)
    $names     = Format-NameList -Names @($drift | ForEach-Object { $_.Name })
    $leftNames = Format-NameList -Names @($left | ForEach-Object { $_.Name })

    if ($left.Count -gt 0) {
        Exit-Script 1 "Failed | Changed=$changed; Failed=$failed; Remaining=$($left.Count); Names=$leftNames"
    }
    if ($DisableHotspotAutoConnect -and ((Get-HotspotAutoConnectValue) -ne 0)) {
        Exit-Script 1 "Failed | Changed=$changed; Failed=$failed; Reason=HotspotAutoConnectNotDisabled"
    }
    Exit-Script 0 "Fixed | Changed=$changed; Failed=$failed; Remaining=0; Names=$names"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
