<#
.SYNOPSIS
  Detection script for explicitly retired WinHTTP and saved WinINET proxy settings.

.DESCRIPTION
  Matches complete proxy strings and PAC URLs against administrator-maintained lists.
  Checks the default WinHTTP configuration, SYSTEM and loaded user Internet Settings.
  Exits 1 for matching leftovers, 0 otherwise. Does not test network reachability.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$StaleProxyServers = @()
$StalePacUrls = @()

$PackageName = 'StaleProxySettings'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Initialize-ProxyApi {
    if ('IRT.ProxyDefaults' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace IRT {
    public static class ProxyDefaults {
        [StructLayout(LayoutKind.Sequential)]
        private struct ProxyInfo {
            public uint Access;
            public IntPtr Proxy;
            public IntPtr Bypass;
        }
        [DllImport("winhttp.dll", SetLastError = true)]
        private static extern bool WinHttpGetDefaultProxyConfiguration(out ProxyInfo info);
        [DllImport("kernel32.dll")]
        private static extern IntPtr GlobalFree(IntPtr memory);
        public static string[] Read() {
            ProxyInfo info;
            if (!WinHttpGetDefaultProxyConfiguration(out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                return new string[] {info.Access.ToString(),
                    Marshal.PtrToStringUni(info.Proxy) ?? "",
                    Marshal.PtrToStringUni(info.Bypass) ?? ""};
            } finally {
                if (info.Proxy != IntPtr.Zero) GlobalFree(info.Proxy);
                if (info.Bypass != IntPtr.Zero) GlobalFree(info.Bypass);
            }
        }
    }
}
'@ -ErrorAction Stop
}
function Test-ProxyPolicy { param([string]$Root)
    $settings = "$Root\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings"
    if (Test-Path -LiteralPath $settings -ErrorAction Stop) { return $true }
    $panel = "$Root\Software\Policies\Microsoft\Internet Explorer\Control Panel"
    if (Test-Path -LiteralPath $panel -ErrorAction Stop) {
        $key = Get-Item -LiteralPath $panel -ErrorAction Stop
        if ($key.GetValueNames() -contains 'Proxy') { return $true }
    }
    return $false
}
function Get-SavedProxyState { param([string]$Root)
    $path = "$Root\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { return }
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    $proxy = [string]$key.GetValue('ProxyServer', '')
    $pac = [string]$key.GetValue('AutoConfigURL', '')
    $staticMatch = $proxy.Length -gt 0 -and $StaleProxyServers -contains $proxy
    $pacMatch = $pac.Length -gt 0 -and $StalePacUrls -ccontains $pac
    if ($staticMatch -or $pacMatch) {
        [pscustomobject]@{ Static = $staticMatch; Pac = $pacMatch; Blocked = (Test-ProxyPolicy -Root $Root) }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Require64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Failed | Reason=RequireSystem'
    }
    if ($StaleProxyServers.Count -eq 0 -and $StalePacUrls.Count -eq 0) {
        Exit-Script 0 'NotApplicable | Reason=ConfigureRetiredValues'
    }
    if (@($StaleProxyServers + $StalePacUrls | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        Exit-Script 1 'Failed | Reason=EmptyListEntry'
    }
    Initialize-ProxyApi
    $winHttp = [IRT.ProxyDefaults]::Read()
    $httpMatch = $winHttp[1].Length -gt 0 -and $StaleProxyServers -contains $winHttp[1]
    $roots = @('Registry::HKEY_CURRENT_USER')
    $roots += @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-\d+(?:-\d+)+$' } |
        ForEach-Object { "Registry::HKEY_USERS\$($_.PSChildName)" })
    $states = @($roots | ForEach-Object { Get-SavedProxyState -Root $_ })
    $machineBlocked = Test-ProxyPolicy -Root 'Registry::HKEY_LOCAL_MACHINE'
    $blocked = @($states | Where-Object { $_.Blocked -or $machineBlocked }).Count
    if ($httpMatch -and $machineBlocked) { $blocked++ }
    $count = $states.Count + [int]$httpMatch
    $summary = "WinHTTP=$([int]$httpMatch); WinINET=$($states.Count); PolicyBlocked=$blocked; Scope=SavedLoadedSettings"
    if ($count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: InspectionFailed | HResult=$($_.Exception.HResult)" }
