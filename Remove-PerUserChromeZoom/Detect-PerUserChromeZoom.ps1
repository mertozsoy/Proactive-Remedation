<#
.SYNOPSIS
  Detection script for Chrome and Zoom installed under a user profile.

.DESCRIPTION
  Looks for the Chrome and Zoom executable under AppData in every local user profile. A copy inside a profile is a per-user install that the machine wide deployment does not update. Exits 1 if at least one per-user install is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetApps = @(
    [pscustomobject]@{ Name = 'Chrome'; Marker = 'AppData\Local\Google\Chrome\Application\chrome.exe' }
    [pscustomobject]@{ Name = 'Zoom'; Marker = 'AppData\Roaming\Zoom\bin\Zoom.exe' }
)

$PackageName = 'PerUserChromeZoom'
$Phase       = 'Detect'
$LogFile     = Join-Path -Path $env:ProgramData -ChildPath "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-LocalProfile {
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special=False' -ErrorAction Stop)
    foreach ($userProfile in $profiles) {
        if (-not $userProfile.SID) { continue }
        if ($userProfile.SID -notmatch '^S-1-5-21-') { continue }
        if (-not $userProfile.LocalPath) { continue }
        if (-not (Test-Path -LiteralPath $userProfile.LocalPath -PathType Container)) { continue }
        $userProfile
    }
}

function Get-PerUserInstall {
    param($UserProfile)
    $found = @()
    foreach ($app in $TargetApps) {
        $exePath = Join-Path -Path $UserProfile.LocalPath -ChildPath $app.Marker
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { continue }
        $found += [pscustomobject]@{
            Name        = $app.Name
            Sid         = $UserProfile.SID
            ProfilePath = $UserProfile.LocalPath
            ExePath     = $exePath
        }
    }
    $found
}

try {
    $profiles = @(Get-LocalProfile)
    if ($profiles.Count -eq 0) { Exit-Script 0 'NotApplicable | UserProfiles=0' }

    $install = @()
    foreach ($userProfile in $profiles) { $install += @(Get-PerUserInstall -UserProfile $userProfile) }

    foreach ($item in $install) {
        $safePath = $item.ExePath.Replace($item.ProfilePath, '<profile>')
        Write-IRTLog ('Per-user install found: {0} at {1}' -f $item.Name, $safePath)
    }

    $counts = @()
    foreach ($app in $TargetApps) {
        $count = @($install | Where-Object { $_.Name -eq $app.Name }).Count
        if ($count -gt 0) { $counts += ('{0}={1}' -f $app.Name, $count) }
    }
    $tail = 'Profiles={0}; PerUser={1}; Scope=AppData' -f $profiles.Count, $install.Count

    if ($install.Count -eq 0) { Exit-Script 0 "Healthy | $tail" }
    Exit-Script 1 ('PerUserInstall | ' + ($counts -join '; ') + '; ' + $tail)
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
