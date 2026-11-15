<#
.SYNOPSIS
  Detection script for passwords saved in Edge and Chrome.

.DESCRIPTION
  Counts the logins stored in the Edge and Chrome password databases of the signed-in user. Each database is copied to a temporary folder and read with the SQLite library that ships with Windows. Exits 1 if at least one saved login is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinimumSavedLogins = 1
$VaultFileNames     = @('Login Data', 'Login Data For Account')
$BrowserTargets     = @(
    @{ Name = 'Edge'; ProcessName = 'msedge'; UserData = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data' }
    @{ Name = 'Chrome'; ProcessName = 'chrome'; UserData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data' }
)

$PackageName = 'SavedBrowserPasswords'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$SqliteInterop = @'
using System;
using System.Runtime.InteropServices;

public static class IrtSqlite
{
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_open_v2(byte[] fileName, out IntPtr db, int flags, IntPtr vfs);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int length, out IntPtr statement, IntPtr tail);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_step(IntPtr statement);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern long sqlite3_column_int64(IntPtr statement, int column);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_finalize(IntPtr statement);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_close(IntPtr db);
}
'@

function Initialize-Sqlite {
    if (-not ([System.Management.Automation.PSTypeName]'IrtSqlite').Type) {
        Add-Type -TypeDefinition $SqliteInterop -ErrorAction Stop
    }
}

function Get-VaultLoginCount { param([string]$VaultPath)
    $workDir = Join-Path $env:TEMP ('IRT_SBP_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir -Force -ErrorAction Stop | Out-Null
    try {
        $copyPath = Join-Path $workDir 'vault.db'
        Copy-Item -LiteralPath $VaultPath -Destination $copyPath -Force -ErrorAction Stop
        $name = [Text.Encoding]::UTF8.GetBytes($copyPath + [string][char]0)
        $db = [IntPtr]::Zero
        if ([IrtSqlite]::sqlite3_open_v2($name, [ref]$db, 1, [IntPtr]::Zero) -ne 0) { throw 'OpenFailed' }
        try {
            foreach ($query in @('SELECT COUNT(*) FROM logins WHERE blacklisted_by_user = 0', 'SELECT COUNT(*) FROM logins')) {
                $statement = [IntPtr]::Zero
                $sqlBytes = [Text.Encoding]::UTF8.GetBytes($query)
                if ([IrtSqlite]::sqlite3_prepare_v2($db, $sqlBytes, $sqlBytes.Length, [ref]$statement, [IntPtr]::Zero) -ne 0) { continue }
                if ($statement -eq [IntPtr]::Zero) { continue }
                try {
                    if ([IrtSqlite]::sqlite3_step($statement) -eq 100) {
                        return [int][IrtSqlite]::sqlite3_column_int64($statement, 0)
                    }
                }
                finally { [void][IrtSqlite]::sqlite3_finalize($statement) }
            }
        }
        finally { [void][IrtSqlite]::sqlite3_close($db) }
        throw 'QueryFailed'
    }
    finally { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-PasswordVault {
    foreach ($browser in $BrowserTargets) {
        if (-not (Test-Path -LiteralPath $browser.UserData -PathType Container)) { continue }
        $profiles = @(Get-ChildItem -LiteralPath $browser.UserData -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile [0-9]+)$' })
        foreach ($browserProfile in $profiles) {
            foreach ($vaultName in $VaultFileNames) {
                $vaultPath = Join-Path $browserProfile.FullName $vaultName
                if (-not (Test-Path -LiteralPath $vaultPath -PathType Leaf)) { continue }
                $savedLogins = -1
                try { $savedLogins = Get-VaultLoginCount -VaultPath $vaultPath } catch { $savedLogins = -1 }
                [pscustomobject]@{
                    Browser     = $browser.Name
                    Profile     = $browserProfile.Name
                    Path        = $vaultPath
                    SavedLogins = $savedLogins
                }
            }
        }
    }
}

function Get-BrowserLoginSum { param($Vaults, [string]$Browser)
    $sum = 0
    foreach ($vault in $Vaults) {
        if ($vault.Browser -eq $Browser -and $vault.SavedLogins -gt 0) { $sum += $vault.SavedLogins }
    }
    $sum
}

try {
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null }
    if ($env:LOCALAPPDATA -like '*\systemprofile*') { Exit-Script 0 'NotApplicable | UserContextRequired' }
    if ($MinimumSavedLogins -lt 1) { throw 'InvalidThreshold' }

    $installed = @($BrowserTargets | Where-Object { Test-Path -LiteralPath $_.UserData -PathType Container })
    if ($installed.Count -eq 0) { Exit-Script 0 'NotApplicable | Browsers=NotInstalled' }

    Initialize-Sqlite
    $vaults = @(Get-PasswordVault)
    if ($vaults.Count -eq 0) { Exit-Script 0 'NotApplicable | PasswordStore=0' }

    foreach ($vault in $vaults) {
        Write-IRTLog ('{0} {1} logins={2} file={3}' -f $vault.Browser, $vault.Profile, $vault.SavedLogins, $vault.Path)
    }

    $withLogins = @($vaults | Where-Object { $_.SavedLogins -ge $MinimumSavedLogins })
    $unreadable = @($vaults | Where-Object { $_.SavedLogins -lt 0 }).Count
    $edgeLogins = Get-BrowserLoginSum -Vaults $vaults -Browser 'Edge'
    $chromeLogins = Get-BrowserLoginSum -Vaults $vaults -Browser 'Chrome'
    $summary = 'Stores={0}; Saved={1}; Edge={2}; Chrome={3}; Unreadable={4}' -f $vaults.Count, ($edgeLogins + $chromeLogins), $edgeLogins, $chromeLogins, $unreadable

    if ($withLogins.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 1 "Drift | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
