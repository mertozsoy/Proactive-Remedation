<#
.SYNOPSIS
  Detection script for a missing wired 802.1X profile on physical Ethernet adapters.

.DESCRIPTION
  Compares the wired profile store of every physical Ethernet adapter with the approved LAN profile XML and checks the Wired AutoConfig service state. Exits 1 if a profile or the service state is wrong, 0 if the device is healthy or the check does not apply.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BaselineProfilePath  = Join-Path $env:ProgramData 'IntuneRemediations\Baseline\Wired8021X.xml'
$InterfaceAliasFilter = @()
$WiredMediumId        = 14
$ProfileStoreRoot     = Join-Path $env:ProgramData 'Microsoft\dot3svc\Profiles\Interfaces'
$WiredPolicyKey       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WiredL2\GP_Policy'
$ServiceName          = 'dot3svc'

$PackageName = 'Wired8021XProfile'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = ($Summary -replace '[\r\n]+', ' ').Trim()
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Test-Dot1xProfileXml {
    param([string]$Path)
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.LoadXml([System.IO.File]::ReadAllText($Path))
    $root = $document.DocumentElement
    if ($null -eq $root -or $root.LocalName -ne 'LANProfile') { return $false }
    $enabled = $document.SelectSingleNode("/*[local-name()='LANProfile']/*[local-name()='MSM']/*[local-name()='security']/*[local-name()='OneXEnabled']")
    if ($null -eq $enabled) { return $false }
    return ($enabled.InnerText.Trim() -eq 'true')
}

function Get-WiredAdapter {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
        ($_.NdisPhysicalMedium -eq $WiredMediumId -or $_.PhysicalMediaType -like '802.3*') -and $_.Status -ne 'Not Present'
    })
    if ($InterfaceAliasFilter.Count -gt 0) {
        $adapters = @($adapters | Where-Object { $InterfaceAliasFilter -contains $_.Name })
    }
    return $adapters
}

function Test-InterfaceProfile {
    param([string]$InterfaceGuid)
    $folder = Join-Path $ProfileStoreRoot $InterfaceGuid
    if (-not (Test-Path -LiteralPath $folder)) { return $false }
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
        try {
            if (Test-Dot1xProfileXml -Path $file.FullName) { return $true }
        }
        catch { }
    }
    return $false
}

try {
    if (-not (Test-Path -LiteralPath $BaselineProfilePath)) {
        Exit-Script 0 'NotApplicable | Reason=BaselineProfileMissing'
    }

    $baselineIsDot1x = $false
    try { $baselineIsDot1x = Test-Dot1xProfileXml -Path $BaselineProfilePath }
    catch { Exit-Script 1 'Error: Baseline profile XML is not readable' }
    if (-not $baselineIsDot1x) { Exit-Script 0 'NotApplicable | Reason=BaselineIsNotDot1xProfile' }

    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | Reason=WiredAutoConfigServiceMissing' }

    $adapters = @(Get-WiredAdapter)
    if ($adapters.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoWiredAdapter' }

    $missing = @()
    foreach ($adapter in $adapters) {
        if (-not (Test-InterfaceProfile -InterfaceGuid $adapter.InterfaceGuid)) { $missing += $adapter.Name }
    }

    $policyManaged = Test-Path -LiteralPath $WiredPolicyKey
    if ($missing.Count -eq 0 -and $service.StartMode -ne 'Disabled') {
        Exit-Script 0 "Healthy | WiredAdapters=$($adapters.Count); Dot1xProfiles=$($adapters.Count); Service=$($service.StartMode)"
    }

    $detail = "WiredAdapters=$($adapters.Count); Missing=$($missing.Count); Service=$($service.StartMode); PolicyManaged=$policyManaged"
    if ($missing.Count -gt 0) { $detail = $detail + '; Interfaces=' + ($missing -join ',') }
    Exit-Script 1 "Drift | $detail"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
