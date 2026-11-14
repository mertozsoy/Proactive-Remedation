<#
.SYNOPSIS
  Detection script for oversized Edge and Chrome disk caches in unloaded profiles.

.DESCRIPTION
  Checks default browser locations in local user profiles. Exits 1 if an eligible
  Cache directory reaches the configured size, 0 otherwise. Loaded profiles are excluded.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumCacheMB = 256

$PackageName = 'BrowserCache'
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

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Failed | Reason=RequiresSystem'
    }
    if ($MinimumCacheMB -lt 1) { throw 'InvalidThreshold' }
    $candidates = @(Get-CacheCandidate)
    $loaded = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special=False AND Loaded=True' -ErrorAction Stop).Count
    if ($candidates.Count -eq 0) {
        Exit-Script 0 "Healthy | EligibleCaches=0; LoadedProfilesSkipped=$loaded; ThresholdMB=$MinimumCacheMB"
    }
    $totalMB = [math]::Round(($candidates | Measure-Object -Property Bytes -Sum).Sum / 1MB)
    Exit-Script 1 "Drift | EligibleCaches=$($candidates.Count); CacheMB=$totalMB; LoadedProfilesSkipped=$loaded"
}
catch { Exit-Script 1 "Error: ScanFailed | Type=$($_.Exception.GetType().Name)" }
