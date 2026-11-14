<#
.SYNOPSIS
  Detection script for classic Outlook web link handling.

.DESCRIPTION
  Reads the Windows default browser and the Outlook link preference of the signed-in user. Checks the Office policy value first, then the per-user value in the current user hive. Exits 1 when Outlook is set to open web links in Microsoft Edge while Windows uses another default browser, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$OfficeVersion = '16.0'
$IgnoreWhenDefaultIsEdge = $true
$EdgeProgIdPrefix = 'MSEdge'

$PackageName = 'OutlookBrowserLinks'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$CryptoSource = @'
using System;
using System.Runtime.InteropServices;

public static class OutlookLinkCrypto
{
    [StructLayout(LayoutKind.Sequential)]
    public struct DATA_BLOB
    {
        public int cbData;
        public IntPtr pbData;
    }

    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CryptProtectData(ref DATA_BLOB pDataIn, string szDataDescr, IntPtr pOptionalEntropy, IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DATA_BLOB pDataOut);

    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CryptUnprotectData(ref DATA_BLOB pDataIn, out IntPtr ppszDataDescr, IntPtr pOptionalEntropy, IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DATA_BLOB pDataOut);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr hMem);

    public static byte[] Protect(byte[] data, string description)
    {
        DATA_BLOB input = new DATA_BLOB();
        DATA_BLOB output = new DATA_BLOB();
        input.cbData = data.Length;
        input.pbData = Marshal.AllocHGlobal(data.Length);
        try
        {
            Marshal.Copy(data, 0, input.pbData, data.Length);
            bool ok = CryptProtectData(ref input, description, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0x1, ref output);
            if (!ok) { throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); }
            byte[] result = new byte[output.cbData];
            Marshal.Copy(output.pbData, result, 0, output.cbData);
            return result;
        }
        finally
        {
            if (input.pbData != IntPtr.Zero) { Marshal.FreeHGlobal(input.pbData); }
            if (output.pbData != IntPtr.Zero) { LocalFree(output.pbData); }
        }
    }

    public static byte[] Unprotect(byte[] data)
    {
        DATA_BLOB input = new DATA_BLOB();
        DATA_BLOB output = new DATA_BLOB();
        IntPtr description = IntPtr.Zero;
        input.cbData = data.Length;
        input.pbData = Marshal.AllocHGlobal(data.Length);
        try
        {
            Marshal.Copy(data, 0, input.pbData, data.Length);
            bool ok = CryptUnprotectData(ref input, out description, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0x1, ref output);
            if (!ok) { throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); }
            byte[] result = new byte[output.cbData];
            Marshal.Copy(output.pbData, result, 0, output.cbData);
            return result;
        }
        finally
        {
            if (description != IntPtr.Zero) { LocalFree(description); }
            if (input.pbData != IntPtr.Zero) { Marshal.FreeHGlobal(input.pbData); }
            if (output.pbData != IntPtr.Zero) { LocalFree(output.pbData); }
        }
    }
}
'@

function Get-SystemDefaultBrowser {
    $key = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
    $progId = (Get-ItemProperty -LiteralPath $key -Name 'ProgId' -ErrorAction SilentlyContinue).ProgId
    if ($null -eq $progId) { return '' }
    return [string]$progId
}

function Get-LinkChoice {
    param([string]$PolicyKey, [string]$UserKey)

    $policy = 'NotSet'
    if (Test-Path -LiteralPath $PolicyKey) {
        $value = (Get-ItemProperty -LiteralPath $PolicyKey -Name 'browserchoice' -ErrorAction SilentlyContinue).browserchoice
        if ($null -ne $value) {
            if ([int]$value -eq 1) { $policy = 'Edge' }
            elseif ([int]$value -eq 0) { $policy = 'Default' }
            else { $policy = 'Other' }
        }
    }

    $choice = 'NotSet'
    if (Test-Path -LiteralPath $UserKey) {
        $raw = (Get-ItemProperty -LiteralPath $UserKey -Name 'BrowserChoice' -ErrorAction SilentlyContinue).BrowserChoice
        if ($null -ne $raw) {
            if ($raw -is [byte[]] -and $raw.Length -ge 4) {
                try {
                    $plain = [OutlookLinkCrypto]::Unprotect($raw)
                    if ($plain.Length -ge 4) {
                        $number = [BitConverter]::ToInt32($plain, 0)
                        if ($number -eq 1) { $choice = 'Edge' }
                        elseif ($number -eq 0) { $choice = 'Default' }
                        else { $choice = 'Other' }
                    }
                }
                catch { $choice = 'Unreadable' }
            }
            else { $choice = 'Unreadable' }
        }
    }

    [pscustomobject]@{ Policy = $policy; UserChoice = $choice }
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }
    if (-not (Test-Path -LiteralPath "HKCU:\Software\Microsoft\Office\$OfficeVersion\Outlook")) {
        Exit-Script 0 'NotApplicable | ClassicOutlook=NotInitialized'
    }

    $progId = Get-SystemDefaultBrowser
    if ([string]::IsNullOrWhiteSpace($progId)) { Exit-Script 0 'NotApplicable | DefaultBrowser=Unknown' }
    if ($progId -like "$EdgeProgIdPrefix*" -and $IgnoreWhenDefaultIsEdge) {
        Exit-Script 0 "NotApplicable | DefaultBrowser=$progId"
    }

    Add-Type -TypeDefinition $CryptoSource -ErrorAction Stop
    $policyKey = "HKCU:\Software\Policies\Microsoft\Office\$OfficeVersion\Common\Links"
    $userKey   = "HKCU:\Software\Microsoft\Office\$OfficeVersion\Common\Links"
    $state     = Get-LinkChoice -PolicyKey $policyKey -UserKey $userKey
    $summary   = 'DefaultBrowser={0}; Policy={1}; UserChoice={2}' -f $progId, $state.Policy, $state.UserChoice

    if ($state.Policy -eq 'Default') { Exit-Script 0 "Healthy | $summary" }
    if ($state.Policy -eq 'Other') { Exit-Script 0 "Healthy | $summary" }
    if ($state.Policy -eq 'Edge') { Exit-Script 0 "PolicyManaged | $summary; Reason=ManagedByPolicy" }
    if ($state.UserChoice -in @('Default', 'Other')) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 1 "Drift | $summary; Expected=DefaultBrowser"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
