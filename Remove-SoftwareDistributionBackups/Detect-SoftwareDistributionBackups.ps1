<#
.SYNOPSIS
  Detection script for stale SoftwareDistribution.old and catroot2.old backup folders.

.DESCRIPTION
  Looks for SoftwareDistribution.old and catroot2.old folders left behind by earlier Windows Update repairs. A folder counts as stale when the live folder still exists and the backup is older than the age limit. Exits 1 if at least one stale backup is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 7
$MaximumEntries = 200000

$PackageName = 'SoftwareDistributionBackups'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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
function Get-BackupTarget {
    $root = $env:SystemRoot
    @(
        [pscustomobject]@{ Name = 'SoftwareDistribution.old'; Path = (Join-Path $root 'SoftwareDistribution.old'); LivePath = (Join-Path $root 'SoftwareDistribution') }
        [pscustomobject]@{ Name = 'catroot2.old'; Path = (Join-Path $root 'System32\catroot2.old'); LivePath = (Join-Path $root 'System32\catroot2') }
    )
}
function Get-BackupStamp { param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
    if ($item.LastWriteTimeUtc -gt $item.CreationTimeUtc) { return $item.LastWriteTimeUtc }
    $item.CreationTimeUtc
}
function Measure-BackupTree { param([string]$Path)
    [long]$bytes = 0
    $count = 0
    $reparse = $false
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Path)
    while ($pending.Count -gt 0) {
        $item = Get-Item -LiteralPath $pending.Pop() -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $reparse = $true; continue }
        $count++
        if ($count -gt $MaximumEntries) { throw 'EntryLimitExceeded' }
        if (-not $item.PSIsContainer) { $bytes += $item.Length; continue }
        foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop)) {
            $pending.Push($child.FullName)
        }
    }
    [pscustomobject]@{ Bytes = $bytes; Entries = $count; Reparse = $reparse }
}
function Get-BackupInventory { param([DateTime]$Cutoff)
    $stale = New-Object 'System.Collections.Generic.List[object]'
    $issues = 0
    $held = 0
    foreach ($target in Get-BackupTarget) {
        if (-not (Test-Path -LiteralPath $target.Path -PathType Container)) { continue }
        if (-not (Test-Path -LiteralPath $target.LivePath -PathType Container)) { $held++; continue }
        try {
            $stamp = Get-BackupStamp -Path $target.Path
            if ($null -eq $stamp) { $issues++; continue }
            if ($stamp -ge $Cutoff) { continue }
            $tree = Measure-BackupTree -Path $target.Path
            if ($tree.Reparse) { $issues++; continue }
            $ageDays = [int][math]::Floor(([DateTime]::UtcNow - $stamp).TotalDays)
            $stale.Add([pscustomobject]@{ Name = $target.Name; Path = $target.Path; Bytes = $tree.Bytes; AgeDays = $ageDays })
        }
        catch { $issues++ }
    }
    [pscustomobject]@{ Stale = $stale.ToArray(); Issues = $issues; HeldByLiveMissing = $held }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 1 -or $MinimumAgeDays -gt 365 -or $MaximumEntries -lt 1) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }

    $cutoff = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    $inventory = Get-BackupInventory -Cutoff $cutoff
    $stale = @($inventory.Stale)

    if ($stale.Count -eq 0) {
        Exit-Script 0 "Healthy | StaleBackups=0; HeldByLiveMissing=$($inventory.HeldByLiveMissing); Unreadable=$($inventory.Issues)"
    }

    [long]$totalBytes = 0
    foreach ($entry in $stale) { $totalBytes += $entry.Bytes }
    $list = ($stale | ForEach-Object { '{0}({1}MB/{2}d)' -f $_.Name, [math]::Floor($_.Bytes / 1MB), $_.AgeDays }) -join ','
    Exit-Script 1 "StaleBackups | Count=$($stale.Count); SizeMB=$([math]::Floor($totalBytes / 1MB)); Folders=$list; HeldByLiveMissing=$($inventory.HeldByLiveMissing)"
}
catch { Exit-Script 1 ('Error: {0}' -f $_.Exception.Message) }
