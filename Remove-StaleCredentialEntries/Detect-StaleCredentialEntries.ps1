<#
.SYNOPSIS
  Detection script for stale Credential Manager entries.

.DESCRIPTION
  Reads the persisted credentials of the signed-in user and matches the target names against the retired target list. Exits 1 if a retired target still has a stored credential, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RetiredTargets = @(
    'TERMSRV/legacyfs01.contoso.local'
    'legacyfs01.contoso.local'
)
$KeepTargets = @()
$TargetTypes = @(1, 2)

$PackageName = 'StaleCredentialEntries'
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

if (-not ('IRT.CredentialStore' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace IRT {
    public class CredentialInfo {
        public string Target;
        public uint Type;
        public uint Persist;
    }

    public static class CredentialStore {
        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME {
            public uint Low;
            public uint High;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL {
            public uint Flags;
            public uint Type;
            [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
            [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
            public FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
            [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
        }

        [DllImport("advapi32.dll", EntryPoint = "CredEnumerateW", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CredEnumerate(string filter, int flags, out int count, out IntPtr credentials);

        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);

        public static CredentialInfo[] List() {
            int count;
            IntPtr pointer;
            if (!CredEnumerate(null, 0, out count, out pointer)) {
                int error = Marshal.GetLastWin32Error();
                if (error == 1168 || error == 1312) { return new CredentialInfo[0]; }
                throw new Win32Exception(error);
            }
            CredentialInfo[] result = new CredentialInfo[count];
            try {
                for (int i = 0; i < count; i++) {
                    IntPtr item = Marshal.ReadIntPtr(pointer, i * IntPtr.Size);
                    CREDENTIAL value = (CREDENTIAL)Marshal.PtrToStructure(item, typeof(CREDENTIAL));
                    CredentialInfo info = new CredentialInfo();
                    info.Target = value.TargetName;
                    info.Type = value.Type;
                    info.Persist = value.Persist;
                    result[i] = info;
                }
            }
            finally { CredFree(pointer); }
            return result;
        }
    }
}
'@ -ErrorAction Stop
}

function Test-TargetMatch { param([string]$Target, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($pattern -match '[*?]') {
            if ($Target -like $pattern) { return $true }
        }
        elseif ($Target -eq $pattern) { return $true }
    }
    $false
}

function Get-SafeTarget { param([string]$Target)
    $at = $Target.LastIndexOf('@')
    if ($at -lt 1) { return $Target }
    $masked = $Target.Substring(0, $at) -replace '.', '*'
    return ($masked + $Target.Substring($at))
}

function Get-StaleCredential {
    $stale = @()
    foreach ($credential in @([IRT.CredentialStore]::List())) {
        if ([int]$credential.Persist -eq 1) { continue }
        if ($TargetTypes -notcontains [int]$credential.Type) { continue }
        if (Test-TargetMatch -Target $credential.Target -Patterns $KeepTargets) { continue }
        if (-not (Test-TargetMatch -Target $credential.Target -Patterns $RetiredTargets)) { continue }
        $stale += $credential
    }
    $stale
}

try {
    if ($RetiredTargets.Count -eq 0) { Exit-Script 0 'NotApplicable | RetiredTargets=0' }

    $stale = @(Get-StaleCredential)
    if ($stale.Count -eq 0) { Exit-Script 0 'Healthy | Stale=0' }

    $names = @($stale | ForEach-Object { Get-SafeTarget -Target $_.Target }) -join ','
    Exit-Script 1 "Stale | Count=$($stale.Count); Targets=$names"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
