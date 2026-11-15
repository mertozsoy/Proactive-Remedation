<#
.SYNOPSIS
  Remediation script that deletes passwords saved in Edge and Chrome.

.DESCRIPTION
  Counts the logins in the Edge and Chrome password databases of the signed-in user. With DeleteSavedPasswords enabled it copies each database to a backup folder and deletes the file so the browser starts a clean password store. Exits 0 when no saved login is left, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$DeleteSavedPasswords = $false
$BackupVaultFiles     = $true
$SkipRunningBrowsers  = $true
$MinimumSavedLogins   = 1
$VaultFileNames       = @('Login Data', 'Login Data For Account')
$BrowserTargets       = @(
    @{ Name = 'Edge'; ProcessName = 'msedge'; UserData = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data' }
    @{ Name = 'Chrome'; ProcessName = 'chrome'; UserData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data' }
)

$PackageName = 'SavedBrowserPasswords'
$Phase       = 'Remediate'
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

function Test-SafeVaultPath { param($Vault)
    $root = $null
    foreach ($browser in $BrowserTargets) { if ($browser.Name -eq $Vault.Browser) { $root = $browser.UserData } }
    if (-not $root) { return $false }
    $full = [IO.Path]::GetFullPath($Vault.Path)
    $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\')
    if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    return $true
}

function New-VaultBackup { param($Vault, [string]$BackupRoot)
    $name = '{0}_{1}_{2}.bak' -f $Vault.Browser, ($Vault.Profile -replace ' ', ''), ([IO.Path]::GetFileName($Vault.Path) -replace ' ', '')
    $target = Join-Path $BackupRoot $name
    Copy-Item -LiteralPath $Vault.Path -Destination $target -Force -ErrorAction Stop
    $target
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
    if ($withLogins.Count -eq 0) { Exit-Script 0 'Healthy | SavedPasswords=0' }

    $savedTotal = 0
    foreach ($vault in $withLogins) { $savedTotal += $vault.SavedLogins }
    $browsers = (@($withLogins | Select-Object -ExpandProperty Browser -Unique) | Sort-Object) -join ','
    $running = @($installed | Where-Object { Get-Process -Name $_.ProcessName -ErrorAction SilentlyContinue } | ForEach-Object { $_.Name })
    $runningText = 'None'
    if ($running.Count -gt 0) { $runningText = $running -join ',' }

    if (-not $DeleteSavedPasswords) {
        Exit-Script 1 "ReportOnly | Saved=$savedTotal; Stores=$($withLogins.Count); Browsers=$browsers; Running=$runningText; DeleteSavedPasswords=False"
    }

    $backupRoot = $null
    if ($BackupVaultFiles) {
        $backupRoot = Join-Path $env:LOCALAPPDATA ('IntuneRemediations\Backup\SavedBrowserPasswords\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
    }

    $removed = 0
    $skipped = 0
    $failed = 0
    foreach ($vault in $withLogins) {
        if ($SkipRunningBrowsers -and ($running -contains $vault.Browser)) {
            $skipped++
            Write-IRTLog "Skipped $($vault.Browser) $($vault.Profile): browser running"
            continue
        }
        try {
            if (-not (Test-SafeVaultPath -Vault $vault)) { throw 'UnsafeVaultPath' }
            if ($BackupVaultFiles) { [void](New-VaultBackup -Vault $vault -BackupRoot $backupRoot) }
            Remove-Item -LiteralPath $vault.Path -Force -ErrorAction Stop
            foreach ($sidecar in @("$($vault.Path)-journal", "$($vault.Path)-wal")) {
                if (Test-Path -LiteralPath $sidecar) { Remove-Item -LiteralPath $sidecar -Force -ErrorAction SilentlyContinue }
            }
            if (Test-Path -LiteralPath $vault.Path) { throw 'VaultStillPresent' }
            $removed++
            Write-IRTLog "Deleted $($vault.Browser) $($vault.Profile): $($vault.SavedLogins) logins"
        }
        catch {
            $failed++
            Write-IRTLog "Failed $($vault.Browser) $($vault.Profile): $($_.Exception.Message)" 'ERROR'
        }
    }

    $left = @(Get-PasswordVault | Where-Object { $_.SavedLogins -ge $MinimumSavedLogins })
    if ($left.Count -eq 0) {
        $backupText = 'No'
        if ($BackupVaultFiles) { $backupText = 'Yes' }
        Exit-Script 0 "Fixed | Logins=$savedTotal; Stores=$removed; Backup=$backupText"
    }
    $leftBrowsers = (@($left | Select-Object -ExpandProperty Browser -Unique) | Sort-Object) -join ','
    Exit-Script 1 "Partial | RemovedStores=$removed; Skipped=$skipped; Failed=$failed; Left=$($left.Count); Browsers=$leftBrowsers; Running=$runningText"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
