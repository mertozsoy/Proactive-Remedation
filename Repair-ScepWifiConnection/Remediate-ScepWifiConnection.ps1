<#
.SYNOPSIS
  Remediation script for disconnected machine EAP-TLS Wi-Fi after certificate delivery.

.DESCRIPTION
  Requests one connection after the configured machine certificate becomes available.
  Preserves other Wi-Fi connections and verifies the target profile before returning 0.
  Returns 1 for failed connections or blocked prerequisites.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WifiProfileName = ''
$CertificateIssuer = ''
$RequiredCertificateEkuOids = @('1.3.6.1.5.5.7.3.2')
$InterfaceGuid = ''
$MinimumValidityMinutes = 5
$ConnectionTimeoutSeconds = 45

$PackageName = 'ScepWifiConnection'
$Phase = 'Remediate'
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

function Initialize-WlanApi {
    if ('IRT.ScepWifi' -as [type]) { return }
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace IRT {
    public sealed class ScepWifi : IDisposable {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct InterfaceInfo {
            public Guid Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Description;
            public int State;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ConnectionParameters {
            public int Mode;
            [MarshalAs(UnmanagedType.LPWStr)] public string Profile;
            public IntPtr Ssid;
            public IntPtr Bssid;
            public int BssType;
            public uint Flags;
        }
        [DllImport("wlanapi.dll")] private static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr handle);
        [DllImport("wlanapi.dll")] private static extern uint WlanCloseHandle(IntPtr handle, IntPtr reserved);
        [DllImport("wlanapi.dll")] private static extern void WlanFreeMemory(IntPtr memory);
        [DllImport("wlanapi.dll")] private static extern uint WlanEnumInterfaces(IntPtr handle, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] private static extern uint WlanGetProfile(IntPtr handle, ref Guid id, string name, IntPtr reserved, out IntPtr xml, ref uint flags, out uint access);
        [DllImport("wlanapi.dll")] private static extern uint WlanQueryInterface(IntPtr handle, ref Guid id, int opcode, IntPtr reserved, out uint size, out IntPtr data, out int valueType);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] private static extern uint WlanConnect(IntPtr handle, ref Guid id, ref ConnectionParameters parameters, IntPtr reserved);
        private IntPtr handle;
        public ScepWifi() {
            uint version;
            Check(WlanOpenHandle(2, IntPtr.Zero, out version, out handle), "Open");
        }
        private static void Check(uint result, string operation) {
            if (result != 0) throw new InvalidOperationException("WLAN_" + operation + "_" + result);
        }
        public InterfaceInfo[] Interfaces() {
            IntPtr list = IntPtr.Zero;
            try {
                Check(WlanEnumInterfaces(handle, IntPtr.Zero, out list), "Enumerate");
                int count = Marshal.ReadInt32(list);
                InterfaceInfo[] items = new InterfaceInfo[count];
                int stride = Marshal.SizeOf(typeof(InterfaceInfo));
                for (int i = 0; i < count; i++) items[i] = (InterfaceInfo)Marshal.PtrToStructure(IntPtr.Add(list, 8 + i * stride), typeof(InterfaceInfo));
                return items;
            } finally { if (list != IntPtr.Zero) WlanFreeMemory(list); }
        }
        public string ProfileXml(Guid id, string name) {
            IntPtr xml = IntPtr.Zero;
            uint flags = 0, access;
            try {
                uint result = WlanGetProfile(handle, ref id, name, IntPtr.Zero, out xml, ref flags, out access);
                if (result == 1168) return null;
                Check(result, "Profile");
                if ((flags & 2) != 0) return null;
                return Marshal.PtrToStringUni(xml);
            } finally { if (xml != IntPtr.Zero) WlanFreeMemory(xml); }
        }
        public string CurrentProfile(Guid id) {
            IntPtr data = IntPtr.Zero;
            uint size;
            int valueType;
            try {
                uint result = WlanQueryInterface(handle, ref id, 7, IntPtr.Zero, out size, out data, out valueType);
                if (result == 5023) return null;
                Check(result, "Query");
                if (size < 520) throw new InvalidOperationException("WLAN_Query_Buffer");
                if (Marshal.ReadInt32(data) != 1) return null;
                return Marshal.PtrToStringUni(IntPtr.Add(data, 8), 256).TrimEnd('\0');
            } finally { if (data != IntPtr.Zero) WlanFreeMemory(data); }
        }
        public void Connect(Guid id, string profile) {
            ConnectionParameters p = new ConnectionParameters();
            p.Profile = profile;
            p.BssType = 1;
            Check(WlanConnect(handle, ref id, ref p, IntPtr.Zero), "Connect");
        }
        public void Dispose() {
            if (handle != IntPtr.Zero) { WlanCloseHandle(handle, IntPtr.Zero); handle = IntPtr.Zero; }
        }
    }
}
'@
}

function Get-ReadyCertificateCount {
    $now = Get-Date
    $count = 0
    foreach ($certificate in Get-ChildItem -LiteralPath 'Cert:\LocalMachine\My' -ErrorAction Stop) {
        if ($certificate.Issuer -ne $CertificateIssuer -or -not $certificate.HasPrivateKey) { continue }
        if ($certificate.NotBefore -gt $now -or $certificate.NotAfter -le $now.AddMinutes($MinimumValidityMinutes)) { continue }
        $ekuOids = @($certificate.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId })
        $missing = @($RequiredCertificateEkuOids | Where-Object { $ekuOids -notcontains $_ })
        if ($missing.Count -eq 0) { $count++ }
    }
    return $count
}

function Get-TargetInterface {
    param($Client)
    $interfaces = @($Client.Interfaces())
    if ($InterfaceGuid) { $interfaces = @($interfaces | Where-Object { $_.Id -eq [guid]$InterfaceGuid }) }
    if ($interfaces.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoTargetWlanInterface' }
    if ($interfaces.Count -ne 1) { Exit-Script 1 'Blocked | Reason=SetInterfaceGuid; Candidates=Multiple' }
    return $interfaces[0]
}

function Test-TargetProfile {
    param($Client, [guid]$Id)
    $xmlText = $Client.ProfileXml($Id, $WifiProfileName)
    if (-not $xmlText) { Exit-Script 1 'Blocked | Reason=MachineWifiProfileMissing' }
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.LoadXml($xmlText)
    $profileRoot = "/*[local-name()='WLANProfile']"
    $security = "$profileRoot/*[local-name()='MSM']/*[local-name()='security']"
    $oneX = "$security/*[local-name()='OneX']"
    $name = $document.SelectSingleNode("$profileRoot/*[local-name()='name']")
    $connectionType = $document.SelectSingleNode("$profileRoot/*[local-name()='connectionType']")
    $useOneX = $document.SelectSingleNode("$security/*[local-name()='authEncryption']/*[local-name()='useOneX']")
    $authMode = $document.SelectSingleNode("$oneX/*[local-name()='authMode']")
    $eapType = $document.SelectSingleNode("$oneX/*[local-name()='EAPConfig']/*[local-name()='EapHostConfig']/*[local-name()='EapMethod']/*[local-name()='Type']")
    $certificateStore = $document.SelectSingleNode("$oneX//*[local-name()='CredentialsSource']/*[local-name()='CertificateStore']")
    if ($null -eq $name -or $name.InnerText -cne $WifiProfileName -or $null -eq $connectionType -or $connectionType.InnerText -cne 'ESS' -or $null -eq $useOneX -or $useOneX.InnerText -cne 'true' -or $null -eq $authMode -or $authMode.InnerText -cne 'machine' -or $null -eq $eapType -or $eapType.InnerText -ne '13' -or $null -eq $certificateStore) {
        Exit-Script 0 'NotApplicable | Reason=RequiresMachineEapTlsProfile'
    }
}

$client = $null
try {
    if ([string]::IsNullOrWhiteSpace($WifiProfileName) -or $WifiProfileName.Length -gt 255 -or [string]::IsNullOrWhiteSpace($CertificateIssuer)) {
        Exit-Script 1 'Blocked | Reason=ConfigureProfileNameAndCertificateIssuer'
    }
    if ($MinimumValidityMinutes -lt 0 -or $RequiredCertificateEkuOids -notcontains '1.3.6.1.5.5.7.3.2' -or $ConnectionTimeoutSeconds -lt 5 -or $ConnectionTimeoutSeconds -gt 120) { Exit-Script 1 'Blocked | Reason=InvalidCertificateOrTimeoutSettings' }
    if ($InterfaceGuid) { [void][guid]::Parse($InterfaceGuid) }
    $service = Get-Service -Name 'WlanSvc' -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | Reason=WlanServiceMissing' }
    if ($service.Status -ne 'Running') { Exit-Script 1 'Blocked | Reason=WlanServiceNotRunning' }
    Initialize-WlanApi
    $client = New-Object IRT.ScepWifi
    $target = Get-TargetInterface -Client $client
    Test-TargetProfile -Client $client -Id $target.Id
    $currentProfile = $client.CurrentProfile($target.Id)
    if ($currentProfile -ceq $WifiProfileName) { Exit-Script 0 'Healthy | TargetConnected=True' }
    if ($currentProfile) { Exit-Script 1 'Blocked | Reason=OtherWifiConnected; Action=None' }
    if ($target.State -ne 4) { Exit-Script 1 'Deferred | Reason=InterfaceBusyOrNotReady' }
    $readyCount = Get-ReadyCertificateCount
    if ($readyCount -eq 0) { Exit-Script 1 'Deferred | Reason=WaitingForMachineCertificate; ReadyCertificates=0' }
    if ($readyCount -gt 1) { Exit-Script 1 'Blocked | Reason=AmbiguousMachineCertificates' }
    $fresh = @($client.Interfaces() | Where-Object { $_.Id -eq $target.Id })
    if ($fresh.Count -ne 1 -or $fresh[0].State -ne 4) { Exit-Script 1 'Deferred | Reason=InterfaceStateChanged; Action=None' }
    $client.Connect($target.Id, $WifiProfileName)
    Write-IRTLog 'ConnectRequested | Attempts=1'
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds 2
        $currentProfile = $client.CurrentProfile($target.Id)
        if ($currentProfile -ceq $WifiProfileName) { Exit-Script 0 'Fixed | TargetConnected=True; Attempts=1' }
        if ($currentProfile) { Exit-Script 1 'Failed | Reason=OtherWifiConnectedDuringVerification; Attempts=1' }
    } while ($timer.Elapsed.TotalSeconds -lt $ConnectionTimeoutSeconds)
    Exit-Script 1 'Failed | Reason=ConnectionNotConfirmed; Attempts=1'
}
catch {
    $detail = $_.Exception.GetBaseException().Message
    if ($detail -notmatch '^WLAN_[A-Za-z]+_[0-9]+$') { $detail = 'ConnectionInspectionFailed' }
    Exit-Script 1 "Error: Failed | Reason=$detail"
}
finally {
    if ($null -ne $client) { $client.Dispose() }
}
