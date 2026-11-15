<#
.SYNOPSIS
  Detection script for large Outlook OST files and shared mailbox caching.

.DESCRIPTION
  Reads the Cached Mode policy of every loaded user profile and measures the OST files under the user's Outlook folder. The size is compared with the documented 50 GB default limit or a lower policy value. Exits 1 when a profile has no shared folder cache policy or an OST file is near the limit, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WarnPercent = 80
$CriticalPercent = 95
$DefaultLimitMB = 51200

$PackageName = 'OutlookOstSize'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message)
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Message) -ErrorAction Stop
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 2000) }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-PolicyValue {
    param([string]$KeyPath, [string]$Name)
    $result = [pscustomobject]@{ Exists = $false; Value = $null }
    if (-not (Test-Path -LiteralPath $KeyPath)) { return $result }
    $key = Get-Item -LiteralPath $KeyPath -ErrorAction SilentlyContinue
    if ($null -eq $key) { return $result }
    try {
        if ($key.GetValueNames() -contains $Name) {
            $result.Exists = $true
            $result.Value = $key.GetValue($Name)
        }
    }
    finally { $key.Close() }
    $result
}

function Get-OstFiles {
    param([string]$LocalPath)
    $folder = Join-Path $LocalPath 'AppData\Local\Microsoft\Outlook'
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    @(Get-ChildItem -LiteralPath $folder -Filter '*.ost' -File -ErrorAction SilentlyContinue)
}

try {
    $ErrorActionPreference = 'Stop'
    $userProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Loaded=True AND Special=False' -ErrorAction Stop)
    if ($userProfiles.Count -eq 0) { Exit-Script 0 'NotApplicable | LoadedProfiles=0' }

    $checkedProfiles = 0
    $ostFiles = 0
    $overWarn = 0
    $overCritical = 0
    $missingCache = 0
    $managedProfiles = 0
    $maxPercent = 0
    $minLimitMB = $DefaultLimitMB
    $cacheStates = @()

    foreach ($userProfile in $userProfiles) {
        $sid = [string]$userProfile.SID
        $localPath = [string]$userProfile.LocalPath
        if (-not $sid -or -not $localPath) { continue }
        $hive = 'Registry::HKEY_USERS\' + $sid
        if (-not (Test-Path -LiteralPath ($hive + '\Software\Microsoft\Office\16.0\Outlook'))) { continue }
        $checkedProfiles++

        $files = @(Get-OstFiles -LocalPath $localPath)
        $ostFiles += $files.Count
        $maxBytes = 0
        foreach ($file in $files) {
            if ([int64]$file.Length -gt $maxBytes) { $maxBytes = [int64]$file.Length }
        }

        $limitMB = $DefaultLimitMB
        $limitValue = Get-PolicyValue -KeyPath ($hive + '\Software\Policies\Microsoft\Office\16.0\Outlook\PST') -Name 'MaxLargeFileSize'
        if ($limitValue.Exists) {
            $candidate = 0
            if ([int]::TryParse([string]$limitValue.Value, [ref]$candidate)) {
                if ($candidate -ge 1024 -and $candidate -le $DefaultLimitMB) { $limitMB = $candidate }
            }
        }
        if ($limitMB -lt $minLimitMB) { $minLimitMB = $limitMB }

        $percent = 0
        if ($maxBytes -gt 0) {
            $percent = [int][math]::Round(($maxBytes * 100.0) / ($limitMB * 1MB))
        }
        if ($percent -gt $maxPercent) { $maxPercent = $percent }
        if ($percent -ge $WarnPercent) { $overWarn++ }
        if ($percent -ge $CriticalPercent) { $overCritical++ }

        $cache = Get-PolicyValue -KeyPath ($hive + '\Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode') -Name 'DownloadSharedFolders'
        if (-not $cache.Exists) {
            $missingCache++
            $cacheStates += 'Missing'
        }
        elseif ([int]$cache.Value -eq 0) {
            $cacheStates += 'Disabled'
        }
        else {
            $managedProfiles++
            $cacheStates += 'Enabled'
        }
    }

    if ($checkedProfiles -eq 0) { Exit-Script 0 'NotApplicable | ClassicOutlook=0' }

    $cacheText = (($cacheStates | Sort-Object -Unique) -join '/')
    $limitGB = [int][math]::Round($minLimitMB / 1024.0)
    $drift = $missingCache + $overCritical

    if ($drift -gt 0) {
        Exit-Script 1 "Drift | Profiles=$checkedProfiles; OstFiles=$ostFiles; OverWarn=$overWarn; OverCritical=$overCritical; MaxUsedPct=$maxPercent; LimitGB=$limitGB; SharedCache=$cacheText"
    }
    if ($managedProfiles -gt 0) {
        Exit-Script 0 "PolicyManaged | Profiles=$checkedProfiles; OstFiles=$ostFiles; MaxUsedPct=$maxPercent; LimitGB=$limitGB; SharedCache=$cacheText"
    }
    Exit-Script 0 "Healthy | Profiles=$checkedProfiles; OstFiles=$ostFiles; OverWarn=$overWarn; MaxUsedPct=$maxPercent; LimitGB=$limitGB; SharedCache=$cacheText"
}
catch { Exit-Script 1 ('Error: Failed | Operation=Detect; HResult={0}' -f $_.Exception.HResult) }
