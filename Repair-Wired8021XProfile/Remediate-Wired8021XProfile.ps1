<#
.SYNOPSIS
  Remediation script that restores the wired 802.1X profile from the approved LAN profile XML.

.DESCRIPTION
  Starts the Wired AutoConfig service and adds the approved LAN profile to every physical Ethernet adapter that lost it. Reads the profile store again and exits 0 only when every adapter carries an 802.1X profile.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BaselineProfilePath   = Join-Path $env:ProgramData 'IntuneRemediations\Baseline\Wired8021X.xml'
$InterfaceAliasFilter  = @()
$WiredMediumId         = 14
$ProfileStoreRoot      = Join-Path $env:ProgramData 'Microsoft\dot3svc\Profiles\Interfaces'
$WiredPolicyKey        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WiredL2\GP_Policy'
$ServiceName           = 'dot3svc'
$ProfileWriteTimeout   = 15
$ReconnectInterface    = $false
$SkipWhenPolicyManaged = $true
$EnableRemediation     = $true

$PackageName = 'Wired8021XProfile'
$Phase       = 'Remediate'
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

function Wait-InterfaceProfile {
    param([string]$InterfaceGuid)
    for ($attempt = 0; $attempt -lt $ProfileWriteTimeout; $attempt++) {
        if (Test-InterfaceProfile -InterfaceGuid $InterfaceGuid) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

try {
    if (-not $EnableRemediation) {
        Exit-Script 0 'ReportOnly | Reason=RemediationDisabledByConfiguration'
    }
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

    if ((Test-Path -LiteralPath $WiredPolicyKey) -and $SkipWhenPolicyManaged) {
        Exit-Script 1 'Blocked | Reason=ManagedByWiredPolicy; Action=None'
    }

    if ($service.StartMode -eq 'Disabled') {
        Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop
        Write-IRTLog 'Wired AutoConfig start type set to Manual'
    }
    if ($service.State -ne 'Running') {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-IRTLog 'Wired AutoConfig service started'
    }

    $added = 0
    foreach ($adapter in $adapters) {
        if (Test-InterfaceProfile -InterfaceGuid $adapter.InterfaceGuid) { continue }
        $null = & netsh.exe lan add profile "filename=$BaselineProfilePath" "interface=$($adapter.Name)" 2>&1
        Write-IRTLog "netsh lan add profile interface=$($adapter.Name) exit=$LASTEXITCODE"
        if (Wait-InterfaceProfile -InterfaceGuid $adapter.InterfaceGuid) {
            $added++
            if ($ReconnectInterface) {
                $null = & netsh.exe lan reconnect "interface=$($adapter.Name)" 2>&1
                Write-IRTLog "netsh lan reconnect interface=$($adapter.Name) exit=$LASTEXITCODE"
            }
        }
    }

    $missing = @($adapters | Where-Object { -not (Test-InterfaceProfile -InterfaceGuid $_.InterfaceGuid) })
    foreach ($adapter in $missing) { Write-IRTLog "Profile still missing on $($adapter.Name)" }
    $serviceState = $service.StartMode
    $serviceNow = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($null -ne $serviceNow) { $serviceState = $serviceNow.StartMode }

    if ($missing.Count -eq 0) {
        Exit-Script 0 "Fixed | WiredAdapters=$($adapters.Count); ProfilesAdded=$added; Service=$serviceState"
    }
    Exit-Script 1 ("Failed | Remaining={0}; Added={1}; Interfaces={2}" -f $missing.Count, $added, (($missing | ForEach-Object { $_.Name }) -join ','))
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
