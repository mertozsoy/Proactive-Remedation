<#
.SYNOPSIS
  Remediation script for a known-bad Edge or Chrome extension left in user profiles.

.DESCRIPTION
  Removes the extension folders and user level forcelist entries for the listed IDs. Exits 0 when nothing is left, 1 if a copy remains or the browser was running.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExtensionIds = @()
$SkipWhenBrowserRunning = $true

$PackageName = 'BrowserExtension'
$Phase       = 'Remediate'
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
    $ExtensionIds = @($ExtensionIds | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if ($ExtensionIds.Count -eq 0) { Exit-Script 0 'NotApplicable | ExtensionIds is empty' }

    $processNames = @{ Edge = 'msedge'; Chrome = 'chrome' }
    $removedValues = 0; $removedFolders = 0; $deferred = @()

    foreach ($u in @(Get-UserForcelistEntry)) {
        Remove-ItemProperty -LiteralPath $u.Key -Name $u.Name -ErrorAction Stop
        Write-IRTLog "Removed user forcelist value $($u.Key) [$($u.Name)]"
        $removedValues++
    }

    foreach ($f in @(Get-ExtensionFolder)) {
        if ($SkipWhenBrowserRunning -and (Get-Process -Name $processNames[$f.Browser] -ErrorAction SilentlyContinue)) {
            $deferred += $f.Browser
            Write-IRTLog "$($f.Browser) is running, deferred: $($f.Path)" 'WARN'
            continue
        }
        try {
            Remove-Item -LiteralPath $f.Path -Recurse -Force -ErrorAction Stop
            Write-IRTLog "Removed $($f.Path)"
            $removedFolders++
        } catch { Write-IRTLog "Could not remove $($f.Path): $($_.Exception.Message)" 'WARN' }
    }

    $leftFolders = @(Get-ExtensionFolder).Count
    $leftForce   = @(Get-UserForcelistEntry).Count
    $blocked     = Get-MachinePolicyState -ListName 'ExtensionInstallBlocklist'
    $deferred    = @($deferred | Select-Object -Unique)

    $summary = 'RemovedFolders={0}; RemovedForcelist={1}; LeftFolders={2}; LeftForcelist={3}; Deferred={4}; BlocklistedIn={5}' -f $removedFolders, $removedValues, $leftFolders, $leftForce, ($(if ($deferred) { $deferred -join ',' } else { 'None' })), ($(if ($blocked) { $blocked -join ',' } else { 'None' }))
    if ($leftFolders -eq 0 -and $leftForce -eq 0) { Exit-Script 0 "Removed | $summary" }
    Exit-Script 1 "Incomplete | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
