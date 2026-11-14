<#
.SYNOPSIS
  Remediation script for oversized Edge and Chrome disk caches in unloaded profiles.

.DESCRIPTION
  With RemoveCacheFiles enabled, deletes only files beneath eligible Cache directories.
  Rechecks profile and browser activity and verifies each cache is empty of files.
  Exits 0 after verified cleanup or when no eligible cache exists, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumCacheMB = 256
$RemoveCacheFiles = $false

$PackageName = 'BrowserCache'
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
function Test-SafeLocalPath { param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\') { return $false }
    $current = $full
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $true
}
function Get-CacheFile { param([string]$Path)
    if (-not (Test-SafeLocalPath $Path)) { throw 'UnsafeCachePath' }
    foreach ($entry in Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'ReparsePointInCache' }
        if ($entry.PSIsContainer) { Get-CacheFile $entry.FullName }
        else { $entry }
    }
}
function Get-CacheCandidate {
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)
    foreach ($userProfile in $profiles) {
        if ($userProfile.Special -or $userProfile.Loaded -or -not $userProfile.LocalPath -or $userProfile.Status -ne 0) { continue }
        $profilePath = [IO.Path]::GetFullPath($userProfile.LocalPath).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($profilePath) -ine $usersRoot) { continue }
        if (-not (Test-Path -LiteralPath $profilePath -PathType Container -ErrorAction Stop)) { continue }
        if (-not (Test-SafeLocalPath $profilePath)) { continue }
        foreach ($relative in @('AppData\Local\Microsoft\Edge\User Data', 'AppData\Local\Google\Chrome\User Data')) {
            $root = Join-Path $profilePath $relative
            if (-not (Test-Path -LiteralPath $root -PathType Container -ErrorAction Stop)) { continue }
            if (-not (Test-SafeLocalPath $root)) { continue }
            foreach ($browserProfile in Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop) {
                if ($browserProfile.Name -notmatch '^(Default|Profile [0-9]+)$') { continue }
                if ($browserProfile.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $cache = Join-Path $browserProfile.FullName 'Cache'
                if (-not (Test-Path -LiteralPath $cache -PathType Container -ErrorAction Stop)) { continue }
                if (-not (Test-SafeLocalPath $cache)) { continue }
                $measurement = Get-CacheFile $cache | Measure-Object -Property Length -Sum
                $bytes = [int64]$measurement.Sum
                if ($bytes -ge ($MinimumCacheMB * 1MB)) {
                    [pscustomobject]@{ Path = $cache; SID = $userProfile.SID; Bytes = $bytes }
                }
            }
        }
    }
}
function Assert-CacheIdle { param([string]$SID)
    $userProfile = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$SID'" -ErrorAction Stop)
    if ($userProfile.Count -ne 1 -or $userProfile[0].Loaded) { throw 'ProfileBecameActive' }
    $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" -ErrorAction Stop)
    if ($processes.Count -gt 0) { throw 'BrowserRunning' }
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Failed | Reason=RequiresSystem'
    }
    if ($MinimumCacheMB -lt 1) { throw 'InvalidThreshold' }
    $candidates = @(Get-CacheCandidate)
    if ($candidates.Count -eq 0) { Exit-Script 0 'Healthy | EligibleCaches=0' }
    if (-not $RemoveCacheFiles) {
        Exit-Script 1 "ReportOnly | EligibleCaches=$($candidates.Count); RemoveCacheFiles=False"
    }
    $deleted = 0
    [int64]$removedBytes = 0
    foreach ($candidate in $candidates) {
        Assert-CacheIdle $candidate.SID
        $files = @(Get-CacheFile $candidate.Path)
        foreach ($file in $files) {
            Assert-CacheIdle $candidate.SID
            if (-not (Test-SafeLocalPath $file.FullName)) { throw 'UnsafeCachePath' }
            if (-not $file.FullName.StartsWith($candidate.Path + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'OutsideCacheRoot'
            }
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $file.FullName -ErrorAction Stop) { throw 'FileStillPresent' }
            $deleted++
            $removedBytes += $file.Length
        }
        Assert-CacheIdle $candidate.SID
        if (@(Get-CacheFile $candidate.Path).Count -gt 0) { throw 'CacheNotEmpty' }
    }
    $remaining = @(Get-CacheCandidate)
    if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | RemainingCaches=$($remaining.Count); DeletedFiles=$deleted" }
    $removedMB = [math]::Round($removedBytes / 1MB)
    Exit-Script 0 "Fixed | CleanedCaches=$($candidates.Count); DeletedFiles=$deleted; RemovedMB=$removedMB"
}
catch {
    $reason = 'CleanupFailed'
    if ($_.Exception.Message -in @('BrowserRunning', 'ProfileBecameActive')) { $reason = 'ActivityDetected' }
    Exit-Script 1 "Failed | Reason=$reason; Type=$($_.Exception.GetType().Name)"
}
