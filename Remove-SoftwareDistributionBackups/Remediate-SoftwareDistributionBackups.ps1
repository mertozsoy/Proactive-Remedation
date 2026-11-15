<#
.SYNOPSIS
  Remediation script that deletes stale SoftwareDistribution.old and catroot2.old backup folders.

.DESCRIPTION
  Removes the backup folders left behind by earlier Windows Update repairs, but only when the live folder still exists and the backup is older than the age limit. Takes ownership only when a direct delete is denied. Never restarts services or Windows. Exits 0 when cleanup is complete, 1 when blocked or incomplete.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 7
$MaximumEntries = 200000
$RemoveBackups  = $true

$PackageName = 'SoftwareDistributionBackups'
$Phase       = 'Remediate'
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
function Remove-BackupTree { param([string]$Path)
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch { }
    $takeown = Join-Path $env:SystemRoot 'System32\takeown.exe'
    $icacls  = Join-Path $env:SystemRoot 'System32\icacls.exe'
    $null = & $takeown /F $Path /R /D Y 2>&1
    $null = & $icacls $Path /grant '*S-1-5-18:(OI)(CI)F' /T /C /Q 2>&1
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 1 -or $MinimumAgeDays -gt 365 -or $MaximumEntries -lt 1) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }

    $cutoff = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    $inventory = Get-BackupInventory -Cutoff $cutoff
    $stale = @($inventory.Stale)

    $setup = @(Get-Process -Name 'TrustedInstaller', 'TiWorker', 'SetupHost', 'SetupPlatform' -ErrorAction SilentlyContinue)
    if ($setup.Count -gt 0) {
        Exit-Script 1 "Blocked | Reason=ServicingInProgress; StaleBackups=$($stale.Count); Changed=0"
    }

    if ($stale.Count -eq 0) {
        Exit-Script 0 "Healthy | StaleBackups=0; HeldByLiveMissing=$($inventory.HeldByLiveMissing); Unreadable=$($inventory.Issues)"
    }

    if (-not $RemoveBackups) {
        Exit-Script 1 "ReportOnly | StaleBackups=$($stale.Count); RemoveBackups=False; Changed=0"
    }

    $removed = 0
    $failed = 0
    [long]$removedBytes = 0
    $removedNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $stale) {
        try {
            if (-not (Test-Path -LiteralPath $entry.Path -PathType Container)) { continue }
            if (-not (Remove-BackupTree -Path $entry.Path)) {
                Write-IRTLog "Removal failed: $($entry.Name)" 'WARN'
                $failed++
                continue
            }
            if (Test-Path -LiteralPath $entry.Path) {
                Write-IRTLog "Folder remains: $($entry.Name)" 'WARN'
                $failed++
                continue
            }
            $removed++
            $removedBytes += $entry.Bytes
            $removedNames.Add($entry.Name)
            Write-IRTLog "Removed: $($entry.Name); MB=$([math]::Floor($entry.Bytes / 1MB)); AgeDays=$($entry.AgeDays)"
        }
        catch {
            $failed++
            Write-IRTLog "Removal error: $($entry.Name)" 'WARN'
        }
    }

    $nameText = 'None'
    if ($removedNames.Count -gt 0) { $nameText = $removedNames -join ',' }
    $common = 'StaleBackups={0}; Removed={1}; Failed={2}; RemovedMB={3}; Names={4}; HeldByLiveMissing={5}; Unreadable={6}' -f $stale.Count, $removed, $failed, [math]::Floor($removedBytes / 1MB), $nameText, $inventory.HeldByLiveMissing, $inventory.Issues

    if ($failed -gt 0) { Exit-Script 1 "Failed | $common" }
    Exit-Script 0 "Fixed | $common"
}
catch { Exit-Script 1 ('Error: Operation=None; HResult=0x{0:X8}; Changed=Unknown' -f $_.Exception.HResult) }
