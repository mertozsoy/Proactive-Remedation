<#
.SYNOPSIS
  Detection script for duplicate OneDrive entries in the File Explorer navigation pane.

.DESCRIPTION
  Reads the File Explorer desktop namespace registrations of the signed-in user and the machine, resolves the display name and the target folder of each entry, and reports OneDrive entries that are registered more than once. Exits 1 if a duplicate exists, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$NamePattern = '^OneDrive'
$ReportMachineEntries = $true

$PackageName = 'DuplicateOneDriveEntry'
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

function Get-ClsidName { param([string]$Clsid)
    foreach ($root in @("HKCU:\Software\Classes\CLSID\$Clsid", "HKLM:\SOFTWARE\Classes\CLSID\$Clsid")) {
        $value = (Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue).'(default)'
        if ($value) { return [string]$value }
    }
    return $null
}

function Get-OneDriveEntry { param([string]$RootPath, [string]$Hive)
    if (-not (Test-Path -LiteralPath $RootPath)) { return }

    foreach ($key in @(Get-ChildItem -LiteralPath $RootPath -ErrorAction SilentlyContinue)) {
        $clsid = $key.PSChildName
        $name  = [string](Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).'(default)'
        if (-not $name) { $name = [string](Get-ClsidName -Clsid $clsid) }
        if (-not $name) { continue }
        if ($name -notmatch $NamePattern) { continue }

        if ($Hive -eq 'HKCU') { $classesRoot = "HKCU:\Software\Classes\CLSID\$clsid" }
        else { $classesRoot = "HKLM:\SOFTWARE\Classes\CLSID\$clsid" }

        $target = $null
        $rawTarget = (Get-ItemProperty -LiteralPath (Join-Path $classesRoot 'Instance\InitPropertyBag') -Name 'TargetFolderPath' -ErrorAction SilentlyContinue).TargetFolderPath
        if ($rawTarget) { $target = [Environment]::ExpandEnvironmentVariables([string]$rawTarget) }

        $targetExists = $false
        if ($target) { $targetExists = Test-Path -LiteralPath $target }

        $pinnedValue = (Get-ItemProperty -LiteralPath $classesRoot -Name 'System.IsPinnedToNameSpaceTree' -ErrorAction SilentlyContinue).'System.IsPinnedToNameSpaceTree'
        $pinned = $false
        if ($pinnedValue) { $pinned = ([int]$pinnedValue -ne 0) }

        [pscustomobject]@{
            Name              = $name.Trim()
            Hive              = $Hive
            Clsid             = $clsid
            KeyPath           = $key.PSPath
            TargetExists      = $targetExists
            Pinned            = $pinned
            MachineRegistered = (Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\CLSID\$clsid")
        }
    }
}

function Get-OneDriveEntryState {
    $items = @(Get-OneDriveEntry -RootPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace' -Hive 'HKCU')
    if ($ReportMachineEntries) {
        $items += @(Get-OneDriveEntry -RootPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace' -Hive 'HKLM')
    }
    return $items
}

try {
    $entries = @(Get-OneDriveEntryState)
    if ($entries.Count -eq 0) { Exit-Script 0 'NotApplicable | OneDriveEntries=0' }

    $groups = @{}
    foreach ($entry in $entries) {
        $groupKey = $entry.Name.ToLowerInvariant()
        if (-not $groups.ContainsKey($groupKey)) { $groups[$groupKey] = @() }
        $groups[$groupKey] = @($groups[$groupKey]) + $entry
    }

    $duplicates = @()
    foreach ($groupKey in @($groups.Keys)) {
        if (@($groups[$groupKey]).Count -gt 1) { $duplicates += @($groups[$groupKey]) }
    }

    $names  = (@($entries | Select-Object -ExpandProperty Name -Unique) -join ',')
    $hives  = (@($entries | ForEach-Object { $_.Hive }) -join ',')
    $target = @($entries | Where-Object { $_.TargetExists }).Count

    if ($duplicates.Count -gt 0) {
        $dupNames = (@($duplicates | Select-Object -ExpandProperty Name -Unique) -join ',')
        Exit-Script 1 "Drift | OneDriveEntries=$($entries.Count); DuplicateNames=$dupNames; Hives=$hives; TargetFound=$target"
    }

    Exit-Script 0 "Healthy | OneDriveEntries=$($entries.Count); Names=$names; Hives=$hives; TargetFound=$target"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
