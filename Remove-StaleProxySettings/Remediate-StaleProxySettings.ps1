<#
.SYNOPSIS
  Remediation script for explicitly retired WinHTTP and saved WinINET proxy settings.

.DESCRIPTION
  After approval, backs up and clears exact matches from default WinHTTP and saved
  SYSTEM/loaded user Internet Settings. Preserves unmatched values and policy keys.
  Exits 0 after saved-state verification, 1 for blocked, failed or remaining work.
  EnableRemediation confirms direct access and the absence of active proxy management.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$StaleProxyServers = @()
$StalePacUrls = @()
$EnableRemediation = $false

$PackageName = 'StaleProxySettings'
$Phase = 'Remediate'
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
        [pscustomobject]@{
            Root = $Root; Path = $path; Static = $staticMatch; Pac = $pacMatch
            Proxy = $proxy; Url = $pac; Enabled = $key.GetValue('ProxyEnable', $null)
            Blocked = (Test-ProxyPolicy -Root $Root)
        }
    }
}
function Backup-ProxyKey { param([string]$NativePath, [string]$Destination)
    & "$env:SystemRoot\System32\reg.exe" export $NativePath $Destination /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination)) {
        throw 'RegistryBackupFailed'
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
    if (-not $httpMatch -and $states.Count -eq 0) {
        Exit-Script 0 'Healthy | WinHTTP=0; WinINET=0; Scope=SavedLoadedSettings'
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | WinHTTP=$([int]$httpMatch); WinINET=$($states.Count); Reason=ApprovalRequired"
    }
    if (Test-ProxyPolicy -Root 'Registry::HKEY_LOCAL_MACHINE') {
        Exit-Script 1 'Blocked | Reason=MachineProxyPolicy; Changed=0'
    }
    if (@($states | Where-Object { $_.Blocked }).Count -gt 0) {
        Exit-Script 1 'Blocked | Reason=UserProxyPolicy; Changed=0'
    }
    $backupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    $backupDir = Join-Path $backupRoot ("StaleProxySettings_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
    $acl = Get-Acl -LiteralPath $backupDir -ErrorAction Stop
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sidText in @('S-1-5-18', 'S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $backupDir -AclObject $acl -ErrorAction Stop
    if ($httpMatch) {
        Backup-ProxyKey -NativePath 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections' -Destination (Join-Path $backupDir 'WinHTTP.reg')
    }
    $index = 0
    foreach ($state in $states) {
        $index++
        Backup-ProxyKey -NativePath ($state.Path -replace '^Registry::', '') -Destination (Join-Path $backupDir "WinINET_$index.reg")
    }
    $httpFixed = 0
    $inetFixed = 0
    if ($httpMatch) {
        $current = [IRT.ProxyDefaults]::Read()
        if (($current -join "`n") -cne ($winHttp -join "`n") -or (Test-ProxyPolicy -Root 'Registry::HKEY_LOCAL_MACHINE')) {
            throw 'ConfigurationChanged'
        }
        & "$env:SystemRoot\System32\netsh.exe" winhttp reset proxy 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'WinHTTPResetFailed' }
        $verified = [IRT.ProxyDefaults]::Read()
        if ($verified[0] -ne '1' -or $verified[1].Length -gt 0) { throw 'WinHTTPVerificationFailed' }
        $httpFixed = 1
    }
    foreach ($state in $states) {
        $current = Get-SavedProxyState -Root $state.Root
        if ($null -eq $current -or $current.Proxy -cne $state.Proxy -or $current.Url -cne $state.Url -or
            $current.Enabled -ne $state.Enabled -or $current.Blocked -or
            (Test-ProxyPolicy -Root 'Registry::HKEY_LOCAL_MACHINE')) { throw 'ConfigurationChanged' }
        if ($state.Static) {
            New-ItemProperty -LiteralPath $state.Path -Name 'ProxyEnable' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Remove-ItemProperty -LiteralPath $state.Path -Name 'ProxyServer' -ErrorAction Stop
        }
        if ($state.Pac) { Remove-ItemProperty -LiteralPath $state.Path -Name 'AutoConfigURL' -ErrorAction Stop }
        $key = Get-Item -LiteralPath $state.Path -ErrorAction Stop
        if ($state.Static -and ($key.GetValue('ProxyEnable', -1) -ne 0 -or $key.GetValueNames() -contains 'ProxyServer')) {
            throw 'WinINETVerificationFailed'
        }
        if ($state.Pac -and $key.GetValueNames() -contains 'AutoConfigURL') { throw 'PacVerificationFailed' }
        $inetFixed++
    }
    $remaining = @($roots | ForEach-Object { Get-SavedProxyState -Root $_ }).Count
    $current = [IRT.ProxyDefaults]::Read()
    if ($current[1].Length -gt 0 -and $StaleProxyServers -contains $current[1]) { $remaining++ }
    if ($remaining -gt 0) { Exit-Script 1 "Failed | Remaining=$remaining; WinHTTP=$httpFixed; WinINET=$inetFixed" }
    Exit-Script 0 "Fixed | WinHTTP=$httpFixed; WinINET=$inetFixed; Verified=SavedSettings; Backup=Created"
}
catch { Exit-Script 1 "Error: RemediationIncomplete | HResult=$($_.Exception.HResult); Backup=InspectBeforeRetry" }
