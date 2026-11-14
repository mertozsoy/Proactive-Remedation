<#
.SYNOPSIS
  User-assisted remediation script for browser and mail protocol defaults.

.DESCRIPTION
  Optionally opens Windows Default apps settings and waits for the user to select the expected handlers. Exits 0 only when effective associations match. Silent changes to protected defaults are not attempted. The settings launch is disabled by default.

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
$EnableUserAssistedRemediation = $false
$AssociationPolicyAbsentConfirmed = $false
$WaitSeconds = 180
$PollSeconds = 5

$PackageName = 'UserAppDefaults'
$Phase = 'Remediate'
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
    if (@($states | Where-Object { -not $_.Matches }).Count -eq 0) { Exit-Script 0 'Healthy | Defaults=Match' }
    if (-not $EnableUserAssistedRemediation) { Exit-Script 1 'PendingUserAction | SettingsLaunch=Disabled; Defaults=Mismatch' }
    if (-not $AssociationPolicyAbsentConfirmed) { Exit-Script 1 'Blocked | Reason=ConfirmNoAssociationPolicy' }
    if ($WaitSeconds -lt 5 -or $WaitSeconds -gt 600 -or $PollSeconds -lt 1 -or $PollSeconds -gt 30) {
        Exit-Script 1 'Failed | Reason=InvalidWaitConfiguration'
    }
    if (-not [Environment]::UserInteractive) { Exit-Script 1 'PendingUserAction | Reason=NoInteractiveDesktop' }
    Start-Process -FilePath 'ms-settings:defaultapps' -ErrorAction Stop | Out-Null
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds $PollSeconds
        $states = @(Get-DefaultState)
        if (@($states | Where-Object { -not $_.Matches }).Count -eq 0) {
            Exit-Script 0 'Fixed | Defaults=Match; Method=WindowsSettingsUserChoice'
        }
    } while ($timer.Elapsed.TotalSeconds -lt $WaitSeconds)
    $remaining = (@($states | Where-Object { -not $_.Matches } | ForEach-Object { $_.Protocol }) -join ',')
    Exit-Script 1 "PendingUserAction | Remaining=$remaining; SettingsOpened=True"
} catch { Exit-Script 1 ('Error: RemediationFailed | HResult={0}' -f $_.Exception.HResult) }
