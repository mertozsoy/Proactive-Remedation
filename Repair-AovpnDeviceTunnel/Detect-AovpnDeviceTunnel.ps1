<#
.SYNOPSIS
  Detects a missing Always On VPN device tunnel profile.

.DESCRIPTION
  Checks the device VPN CSP and all-user VPN connections. Exits 1 for a missing or inconsistent profile, 0 for a present profile or an unsupported device. Does not test VPN connectivity.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProfileName = ''
$ProfileOwner = 'Unconfigured'

$PackageName = 'AovpnDeviceTunnel'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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
function ConvertTo-ProfileDocument {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'Profile XML is empty.' }
    if ($Text.TrimStart().StartsWith('&lt;')) { $Text = [System.Net.WebUtility]::HtmlDecode($Text) }
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($Text)), $settings)
    try { $document.Load($reader) } finally { $reader.Dispose() }
    if ($document.DocumentElement.Name -cne 'VPNProfile') { throw 'Invalid VPN profile root.' }
    return ,$document
}
function Get-TunnelState {
    $profiles = @(Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_VPNv2_01' -ErrorAction Stop)
    $connections = @(Get-VpnConnection -AllUserConnection -ErrorAction Stop)
    $target = @($profiles | Where-Object { [uri]::UnescapeDataString($_.InstanceID) -eq $ProfileName })
    $connection = @($connections | Where-Object { $_.Name -eq $ProfileName })
    $deviceTunnels = @()
    foreach ($vpnProfile in $profiles) {
        $document = ConvertTo-ProfileDocument -Text $vpnProfile.ProfileXML
        if ([string]$document.VPNProfile.DeviceTunnel -eq 'true') { $deviceTunnels += $vpnProfile }
    }
    if ($target.Count -gt 0 -or $connection.Count -gt 0) {
        if ($target.Count -ne 1 -or $connection.Count -ne 1) { return 'ExistingProfileNeedsReview' }
        $document = ConvertTo-ProfileDocument -Text $target[0].ProfileXML
        if ([string]$document.VPNProfile.DeviceTunnel -ne 'true' -or [string]$document.VPNProfile.AlwaysOn -ne 'true' -or $deviceTunnels.Count -ne 1) { return 'ExistingProfileNeedsReview' }
        return 'Present'
    }
    if ($deviceTunnels.Count -gt 0) { return 'OtherDeviceTunnel' }
    return 'Missing'
}

try {
    if (-not [Environment]::Is64BitProcess -or [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { Exit-Script 1 'Failed | Reason=Requires64BitSystem' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 16299 -or -not $computer.PartOfDomain) { Exit-Script 0 'NotApplicable | Reason=RequiresSupportedDomainJoinedClient' }
    if ([string]::IsNullOrWhiteSpace($ProfileName) -or $ProfileName -ne $ProfileName.Trim() -or $ProfileName -match '[\r\n]' -or $ProfileOwner -notin @('Script', 'Policy')) { Exit-Script 1 'Failed | Reason=ConfigureProfileNameAndOwner' }
    $state = Get-TunnelState
    if ($state -eq 'Present') { Exit-Script 0 'Healthy | DeviceTunnel=Present; Connectivity=NotTested' }
    Exit-Script 1 "Drift | DeviceTunnel=$state; Owner=$ProfileOwner"
}
catch { Exit-Script 1 ('Error: Failed | Reason=InspectionError; HResult={0}' -f $_.Exception.HResult) }
