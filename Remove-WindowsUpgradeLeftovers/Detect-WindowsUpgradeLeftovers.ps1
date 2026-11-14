<#
.SYNOPSIS
  Detection script for Windows upgrade leftovers on the system drive.

.DESCRIPTION
  Checks Windows.old, $WINDOWS.~BT and $WINDOWS.~WS against the rollback age limit. Exits 1 when an eligible leftover folder is found, 0 otherwise. Reports only and deletes nothing.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 10
$LeftoverNames  = @('Windows.old', '$WINDOWS.~BT', '$WINDOWS.~WS')
$MaximumEntries = 500000

$PackageName = 'WindowsUpgradeLeftovers'
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
function Get-LeftoverRoot { param([string]$Name)
    Join-Path ($env:SystemDrive + '\') $Name
}
function Get-LeftoverStamp { param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
    if ($item.LastWriteTimeUtc -gt $item.CreationTimeUtc) { return $item.LastWriteTimeUtc }
    $item.CreationTimeUtc
}
function Measure-LeftoverTree { param([string]$Path)
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
function Get-LeftoverInventory { param([DateTime]$Cutoff)
    $eligible = New-Object 'System.Collections.Generic.List[object]'
    $issues = 0
    foreach ($name in $LeftoverNames) {
        $path = Get-LeftoverRoot -Name $name
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        try {
            $stamp = Get-LeftoverStamp -Path $path
            if ($null -eq $stamp) { $issues++; continue }
            if ($stamp -ge $Cutoff) { continue }
            $tree = Measure-LeftoverTree -Path $path
            if ($tree.Reparse) { $issues++; continue }
            $ageDays = [int][math]::Floor(([DateTime]::UtcNow - $stamp).TotalDays)
            $eligible.Add([pscustomobject]@{ Name = $name; Path = $path; Bytes = $tree.Bytes; AgeDays = $ageDays })
        }
        catch { $issues++ }
    }
    [pscustomobject]@{ Eligible = $eligible.ToArray(); Issues = $issues }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 1 -or $MinimumAgeDays -gt 365 -or $MaximumEntries -lt 1) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=ServerOS' }

    $inventory = Get-LeftoverInventory -Cutoff ([DateTime]::UtcNow.AddDays(-$MinimumAgeDays))
    $eligible = @($inventory.Eligible)
    [long]$totalBytes = 0
    foreach ($entry in $eligible) { $totalBytes += $entry.Bytes }
    $nameText = 'None'
    if ($eligible.Count -gt 0) { $nameText = ($eligible | ForEach-Object { $_.Name }) -join ',' }
    $oldestDays = 0
    if ($eligible.Count -gt 0) { $oldestDays = ($eligible | Measure-Object -Property AgeDays -Maximum).Maximum }

    $summary = 'Leftovers={0}; EligibleMB={1}; OldestDays={2}; Names={3}; MinAgeDays={4}; Issues={5}' -f $eligible.Count, [math]::Floor($totalBytes / 1MB), $oldestDays, $nameText, $MinimumAgeDays, $inventory.Issues
    if ($inventory.Issues -gt 0) { Exit-Script 1 "Review | $summary" }
    if ($eligible.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error | Reason=ScanFailed; Type={0}' -f $_.Exception.GetType().Name) }
