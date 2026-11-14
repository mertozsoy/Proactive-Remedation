<#
.SYNOPSIS
  Remediation script for Windows upgrade leftovers and component store cleanup.

.DESCRIPTION
  Removes Windows.old, $WINDOWS.~BT and $WINDOWS.~WS folders that are past the rollback age limit. Takes ownership only when a direct delete is denied. Runs DISM StartComponentCleanup and verifies the result. Never restarts Windows. Exits 0 when cleanup is complete, 1 when blocked or incomplete.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays        = 10
$LeftoverNames         = @('Windows.old', '$WINDOWS.~BT', '$WINDOWS.~WS')
$MaximumEntries        = 500000
$RemoveLeftovers       = $true
$CleanupComponentStore = $true
$ResetBase             = $false

$PackageName = 'WindowsUpgradeLeftovers'
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
function Remove-LeftoverTree { param([string]$Path)
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
function Invoke-ComponentStoreCleanup {
    $dism = Join-Path $env:SystemRoot 'System32\Dism.exe'
    if (-not (Test-Path -LiteralPath $dism)) { return 'DismMissing' }
    $dismArguments = @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart')
    if ($ResetBase) { $dismArguments += '/ResetBase' }
    $null = & $dism @dismArguments 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 0) { return 'Cleaned' }
    if ($code -eq 3010) { return 'PendingRestart' }
    return ('Failed:0x{0:X8}' -f $code)
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 1 -or $MinimumAgeDays -gt 365 -or $MaximumEntries -lt 1) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Failed | Reason=RequiresSystem'
    }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=ServerOS' }

    $cutoff = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    $inventory = Get-LeftoverInventory -Cutoff $cutoff
    $eligible = @($inventory.Eligible)

    $setup = @(Get-Process -Name 'SetupHost', 'SetupPlatform', 'SetupPrep' -ErrorAction SilentlyContinue)
    if ($setup.Count -gt 0) {
        Exit-Script 1 "Blocked | Reason=UpgradeInProgress; Leftovers=$($eligible.Count); Changed=0"
    }

    if ($eligible.Count -gt 0 -and -not $RemoveLeftovers) {
        Exit-Script 1 "ReportOnly | Leftovers=$($eligible.Count); RemoveLeftovers=False; Changed=0"
    }

    $removed = 0
    $failed = 0
    [long]$removedBytes = 0
    $removedNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $eligible) {
        try {
            $current = Get-LeftoverStamp -Path $entry.Path
            if ($null -eq $current -or $current -ge $cutoff) { $failed++; continue }
            if (-not (Remove-LeftoverTree -Path $entry.Path)) {
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

    $storeState = 'Skipped'
    if ($CleanupComponentStore) {
        try { $storeState = Invoke-ComponentStoreCleanup }
        catch { $storeState = 'Error' }
    }

    $nameText = 'None'
    if ($removedNames.Count -gt 0) { $nameText = $removedNames -join ',' }
    $restartNeeded = $storeState -eq 'PendingRestart'
    $common = 'Leftovers={0}; Removed={1}; Failed={2}; RemovedMB={3}; Names={4}; ComponentStore={5}; Issues={6}; RestartNeeded={7}' -f $eligible.Count, $removed, $failed, [math]::Floor($removedBytes / 1MB), $nameText, $storeState, $inventory.Issues, $restartNeeded

    if ($failed -gt 0) { Exit-Script 1 "Failed | $common" }
    if ($storeState -like 'Failed*' -or $storeState -eq 'Error') { Exit-Script 1 "Failed | $common" }
    if ($eligible.Count -eq 0) { Exit-Script 0 "Healthy | $common" }
    Exit-Script 0 "Fixed | $common"
}
catch { Exit-Script 1 ('Error: Operation=None; HResult=0x{0:X8}; Changed=Unknown' -f $_.Exception.HResult) }
