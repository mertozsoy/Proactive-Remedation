<#
.SYNOPSIS
  Detection script for current-user browser and mail protocol defaults.

.DESCRIPTION
  Queries effective associations through Windows Shell. Exits 1 on drift or query errors and 0 when the configured defaults match. Does not change associations.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedDefaults = [ordered]@{
    http = 'MSEdgeHTM'
    https = 'MSEdgeHTM'
    mailto = 'Outlook.URL.mailto.15'
}

$PackageName = 'UserAppDefaults'
$Phase = 'Detect'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null }
        Add-Content -LiteralPath $LogFile -Value ('{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}
function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Initialize-AssociationQuery {
    if ('IRT.DefaultAssociationQuery' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace IRT {
    [ComImport, Guid("4e530b0a-e611-4c77-a3ac-9031d022281b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAssociationQuery {
        [PreserveSig]
        int QueryCurrentDefault([MarshalAs(UnmanagedType.LPWStr)] string query, int type, int level, out IntPtr result);
    }
    public static class DefaultAssociationQuery {
        public static string Read(string protocol) {
            object instance = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("591209c7-767b-42b2-9fba-44ee4615f2c7")));
            IntPtr result = IntPtr.Zero;
            try {
                int hr = ((IAssociationQuery)instance).QueryCurrentDefault(protocol, 1, 1, out result);
                if (hr == unchecked((int)0x80070483)) return String.Empty;
                Marshal.ThrowExceptionForHR(hr);
                return Marshal.PtrToStringUni(result) ?? String.Empty;
            } finally {
                if (result != IntPtr.Zero) Marshal.FreeCoTaskMem(result);
                Marshal.FinalReleaseComObject(instance);
            }
        }
    }
}
'@ -ErrorAction Stop
}
function Get-DefaultState {
    foreach ($protocol in $ExpectedDefaults.Keys) {
        if ($protocol -notin @('http', 'https', 'mailto') -or [string]::IsNullOrWhiteSpace($ExpectedDefaults[$protocol])) {
            throw 'Invalid expected protocol configuration.'
        }
        $current = [IRT.DefaultAssociationQuery]::Read($protocol)
        [pscustomobject]@{ Protocol = $protocol; Matches = ($current -eq $ExpectedDefaults[$protocol]) }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem -or [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        Exit-Script 0 'NotApplicable | Context=NonUserSession'
    }
    if ($ExpectedDefaults.Count -eq 0) { Exit-Script 1 'Failed | Reason=EmptyConfiguration' }
    Initialize-AssociationQuery
    $states = @(Get-DefaultState)
    $summary = ($states | ForEach-Object { '{0}={1}' -f $_.Protocol, $(if ($_.Matches) { 'Match' } else { 'Mismatch' }) }) -join '; '
    if (@($states | Where-Object { -not $_.Matches }).Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
} catch { Exit-Script 1 ('Error: QueryFailed | HResult={0}' -f $_.Exception.HResult) }
