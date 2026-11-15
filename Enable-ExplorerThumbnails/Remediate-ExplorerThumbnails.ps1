<#
.SYNOPSIS
  Remediation script for Explorer thumbnail previews.

.DESCRIPTION
  Turns thumbnail previews back on for the signed-in user, removes an optional tattooed user policy value and checks the result.
  Exits 0 when thumbnails are enabled, 1 when a policy still forces icons only or the write failed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedIconsOnly = 0
$FixUserPolicy     = $false
$ClearThumbnailCache = $false
$RestartExplorer   = $false

$PackageName = 'ExplorerThumbnails'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
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

function Get-RegistryDword { param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return [int]$item.$Name
}

function Backup-RegistryKey { param([string]$KeyPath, [string]$FileName)
    $targets = @(
        (Join-Path $env:ProgramData 'IntuneRemediations\Backup'),
        (Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup')
    )
    foreach ($dir in $targets) {
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            $file = Join-Path $dir $FileName
            & reg.exe export $KeyPath $file /y 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $file)) { return $file }
        }
        catch { Write-IRTLog "Backup to $dir failed: $($_.Exception.Message)" 'WARN' }
    }
    return $null
}

try {
    $ErrorActionPreference = 'Stop'
    $advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $userPolicyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'

    if (-not (Test-Path -LiteralPath $advancedKey)) { Exit-Script 0 'NotApplicable | Reason=NoLoadedUserProfile' }

    if ($ExpectedIconsOnly -ne 0) { throw 'ExpectedIconsOnly must be 0.' }

    $userPolicy = Get-RegistryDword -Path $userPolicyKey -Name 'DisableThumbnails'
    $current = Get-RegistryDword -Path $advancedKey -Name 'IconsOnly'
    if ($null -eq $userPolicy) { $userPolicy = 0 }
    if ($null -eq $current) { $current = 0 }

    $policyRemoved = $false
    $changed = $false
    if ($userPolicy -eq 1) {
        if (-not $FixUserPolicy) {
            Exit-Script 1 "PolicyBlocked | Location=User; Action=ReviewThumbnailPolicy; Hint=SetFixUserPolicyTrue"
        }
        $backup = Backup-RegistryKey -KeyPath 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -FileName ('ExplorerPolicy_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        if (-not $backup) { Exit-Script 1 'Failed | Reason=PolicyBackupFailed; Action=ReviewThumbnailPolicy' }
        Remove-ItemProperty -LiteralPath $userPolicyKey -Name 'DisableThumbnails' -Force -ErrorAction Stop
        $policyRemoved = $true
        $changed = $true
        Write-IRTLog "Removed DisableThumbnails; backup $backup"
    }

    if ($current -ne $ExpectedIconsOnly) {
        Set-ItemProperty -LiteralPath $advancedKey -Name 'IconsOnly' -Value $ExpectedIconsOnly -Type DWord -ErrorAction Stop
        $changed = $true
        Write-IRTLog "IconsOnly set to $ExpectedIconsOnly from $current"
    }

    $cacheFiles = 0
    if ($ClearThumbnailCache) {
        $cacheDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
        foreach ($file in @(Get-ChildItem -LiteralPath $cacheDir -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue)) {
            try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $cacheFiles++ }
            catch { Write-IRTLog "Cache file in use: $($file.Name)" 'WARN' }
        }
    }

    $restarted = $false
    if ($RestartExplorer) {
        try {
            Stop-Process -Name 'explorer' -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Process -FilePath 'explorer.exe' }
            $restarted = $true
        }
        catch { Write-IRTLog "Explorer restart failed: $($_.Exception.Message)" 'WARN' }
    }
    if ($cacheFiles -gt 0 -or $restarted) { $changed = $true }

    $iconsOnly = Get-RegistryDword -Path $advancedKey -Name 'IconsOnly'
    $userPolicy = Get-RegistryDword -Path $userPolicyKey -Name 'DisableThumbnails'
    if ($null -eq $iconsOnly) { $iconsOnly = 0 }
    if ($null -eq $userPolicy) { $userPolicy = 0 }

    $details = 'IconsOnly={0}; UserPolicy={1}; PolicyRemoved={2}; CacheFiles={3}; ExplorerRestarted={4}' -f $iconsOnly, $userPolicy, $policyRemoved, $cacheFiles, $restarted

    if ($userPolicy -eq 1) { Exit-Script 1 "PolicyBlocked | $details; Location=User; Action=ReviewThumbnailPolicy" }
    if ($iconsOnly -ne $ExpectedIconsOnly) { Exit-Script 1 "Failed | $details" }
    if (-not $changed) { Exit-Script 0 "Healthy | $details" }
    Exit-Script 0 "Fixed | $details"
}
catch { Exit-Script 1 "Failed | Reason=$($_.Exception.Message)" }
