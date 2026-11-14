<#
.SYNOPSIS
  Detection script for a known-bad Edge or Chrome extension left in user profiles.

.DESCRIPTION
  Looks for the listed extension IDs in every Edge and Chrome profile folder and in user level forcelist policies. Exits 1 if any copy is found, 0 if the device is clean.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExtensionIds = @()

$PackageName = 'BrowserExtension'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$BrowserData = @{
    Edge   = 'AppData\Local\Microsoft\Edge\User Data'
    Chrome = 'AppData\Local\Google\Chrome\User Data'
}
$PolicyKeys = @{
    Edge   = 'Software\Policies\Microsoft\Edge'
    Chrome = 'Software\Policies\Google\Chrome'
}

function Get-ExtensionFolder {
    $found = New-Object System.Collections.Generic.List[object]
    $profiles = Get-CimInstance Win32_UserProfile -Filter 'Special=False' | Where-Object { $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) }
    foreach ($p in $profiles) {
        foreach ($browser in $BrowserData.Keys) {
            $root = Join-Path $p.LocalPath $BrowserData[$browser]
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
                foreach ($id in $ExtensionIds) {
                    $path = Join-Path $dir.FullName "Extensions\$id"
                    if (Test-Path -LiteralPath $path) { $found.Add([pscustomobject]@{ Browser = $browser; Id = $id; Path = $path }) }
                }
            }
        }
    }
    return $found
}

function Get-UserForcelistEntry {
    $found = New-Object System.Collections.Generic.List[object]
    $hives = Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' }
    foreach ($hive in $hives) {
        foreach ($browser in $PolicyKeys.Keys) {
            $key = "Registry::HKEY_USERS\$($hive.PSChildName)\$($PolicyKeys[$browser])\ExtensionInstallForcelist"
            if (-not (Test-Path -LiteralPath $key)) { continue }
            $item = Get-Item -LiteralPath $key
            foreach ($name in $item.GetValueNames()) {
                $data = [string]$item.GetValue($name)
                foreach ($id in $ExtensionIds) {
                    if ($data -like "$id*") { $found.Add([pscustomobject]@{ Browser = $browser; Id = $id; Key = $key; Name = $name }) }
                }
            }
        }
    }
    return $found
}

function Get-MachinePolicyState { param([string]$ListName)
    $result = @()
    foreach ($browser in $PolicyKeys.Keys) {
        $key = "HKLM:\$($PolicyKeys[$browser])\$ListName"
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $item = Get-Item -LiteralPath $key
        $values = @($item.GetValueNames() | ForEach-Object { [string]$item.GetValue($_) })
        foreach ($id in $ExtensionIds) {
            if ($values | Where-Object { $_ -like "$id*" -or ($ListName -eq 'ExtensionInstallBlocklist' -and $_ -eq '*') }) { $result += "$browser" }
        }
    }
    return @($result | Select-Object -Unique)
}

try {
    $ExtensionIds = @($ExtensionIds | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if ($ExtensionIds.Count -eq 0) { Exit-Script 0 'NotApplicable | ExtensionIds is empty' }

    $folders   = @(Get-ExtensionFolder)
    $userForce = @(Get-UserForcelistEntry)
    $blocked   = Get-MachinePolicyState -ListName 'ExtensionInstallBlocklist'
    $machForce = Get-MachinePolicyState -ListName 'ExtensionInstallForcelist'

    foreach ($f in $folders)   { Write-IRTLog "Folder: $($f.Path)" 'WARN' }
    foreach ($u in $userForce) { Write-IRTLog "User forcelist: $($u.Key) [$($u.Name)]" 'WARN' }

    $summary = 'Ids={0}; Folders={1}; UserForcelist={2}; BlocklistedIn={3}; MachineForcelist={4}' -f $ExtensionIds.Count, $folders.Count, $userForce.Count, ($(if ($blocked) { $blocked -join ',' } else { 'None' })), ($(if ($machForce) { $machForce -join ',' } else { 'None' }))
    if ($folders.Count -gt 0 -or $userForce.Count -gt 0) { Exit-Script 1 "Found | $summary" }
    Exit-Script 0 "Clean | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
