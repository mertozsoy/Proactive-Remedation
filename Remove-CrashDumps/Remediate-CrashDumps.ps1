<#
.SYNOPSIS
  Remediation script that deletes aged kernel crash dump files.

.DESCRIPTION
  Removes MEMORY.DMP, minidump and live kernel report files older than MinimumAgeDays, then checks that no aged dump is left. Deletes only .dmp files and never changes the configured dump type. Exits 0 when the cleanup is done, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 7
$RemoveFiles    = $true

$PackageName = 'CrashDumps'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}
function Format-SizeMB { param([double]$Bytes)
    [int][math]::Round($Bytes / 1MB)
}
function Get-DumpConfiguration {
    $control = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    $config = [ordered]@{
        DumpFile      = Join-Path $env:SystemRoot 'MEMORY.DMP'
        MinidumpDir   = Join-Path $env:SystemRoot 'Minidump'
        LiveReportDir = Join-Path $env:SystemRoot 'LiveKernelReports'
        DumpType      = 'Unknown'
        AlwaysKeep    = $false
    }
    $values = Get-ItemProperty -LiteralPath $control -ErrorAction SilentlyContinue
    if ($values) {
        if ($values.DumpFile) { $config.DumpFile = ([Environment]::ExpandEnvironmentVariables([string]$values.DumpFile)).Trim() }
        if ($values.MinidumpDir) { $config.MinidumpDir = ([Environment]::ExpandEnvironmentVariables([string]$values.MinidumpDir)).Trim() }
        if ($null -ne $values.AlwaysKeepMemoryDump) { $config.AlwaysKeep = ([int]$values.AlwaysKeepMemoryDump -ne 0) }
        if ($null -ne $values.CrashDumpEnabled) {
            switch ([int]$values.CrashDumpEnabled) {
                0 { $config.DumpType = 'None' }
                1 { $config.DumpType = 'Complete' }
                2 { $config.DumpType = 'Kernel' }
                3 { $config.DumpType = 'Small' }
                7 { $config.DumpType = 'Automatic' }
                default { $config.DumpType = 'Other' }
            }
        }
    }
    $live = Get-ItemProperty -LiteralPath "$control\LiveKernelReports" -ErrorAction SilentlyContinue
    if ($live -and $live.LiveKernelReportsPath) {
        $config.LiveReportDir = (([string]$live.LiveKernelReportsPath).Replace('\??\', '')).Trim()
    }
    [pscustomobject]$config
}
function Get-DumpInventory { param([pscustomobject]$Config)
    $files = New-Object 'System.Collections.Generic.List[object]'
    $seen  = @{}
    $roots = 0
    $targets = @(
        @{ Path = $Config.DumpFile; Recurse = $false },
        @{ Path = $Config.MinidumpDir; Recurse = $false },
        @{ Path = $Config.LiveReportDir; Recurse = $true }
    )
    foreach ($target in $targets) {
        $path = [string]$target.Path
        if (-not $path) { continue }
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $roots++
        $found = @()
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $found = @(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)
        }
        else {
            $found = @(Get-ChildItem -LiteralPath $path -Filter '*.dmp' -File -Force -Recurse:$target.Recurse -ErrorAction SilentlyContinue)
        }
        foreach ($file in $found) {
            if ($null -eq $file -or $file.PSIsContainer) { continue }
            $key = $file.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $files.Add([pscustomobject]@{
                Path    = $file.FullName
                Size    = [double]$file.Length
                Written = $file.LastWriteTime
            })
        }
    }
    [pscustomobject]@{ Files = $files.ToArray(); Roots = $roots }
}

try {
    if ($MinimumAgeDays -lt 1 -or $MinimumAgeDays -gt 365) { Exit-Script 1 'Failed | Reason=InvalidConfiguration' }

    $config    = Get-DumpConfiguration
    $inventory = Get-DumpInventory -Config $config
    if ($inventory.Roots -eq 0) { Exit-Script 0 'NotApplicable | DumpPaths=None' }

    $cutoff   = (Get-Date).AddDays(-$MinimumAgeDays)
    $eligible = @($inventory.Files | Where-Object { $_.Written -lt $cutoff })
    if ($eligible.Count -eq 0) { Exit-Script 0 "Healthy | Files=$($inventory.Files.Count); CleanableMB=0" }

    $cleanBytes = 0.0
    foreach ($file in $eligible) { $cleanBytes += $file.Size }
    if (-not $RemoveFiles) {
        Exit-Script 1 ('ReportOnly | Files={0}; CleanableMB={1}; RemoveFiles=False' -f $eligible.Count, (Format-SizeMB $cleanBytes))
    }

    Write-IRTLog ('DumpType={0} AlwaysKeep={1} ThresholdAge={2}d' -f $config.DumpType, $config.AlwaysKeep, $MinimumAgeDays)

    $removed  = 0
    $failures = 0
    $freed    = 0.0
    foreach ($file in $eligible) {
        try {
            $current = Get-Item -LiteralPath $file.Path -Force -ErrorAction Stop
            if ($current.LastWriteTime -ge $cutoff) { throw 'File changed during cleanup.' }
            Remove-Item -LiteralPath $current.FullName -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $current.FullName) { throw 'File remains.' }
            $removed++
            $freed += [double]$current.Length
            Write-IRTLog ('Removed {0} MB {1}' -f (Format-SizeMB $current.Length), $current.FullName)
        }
        catch {
            if (-not (Test-Path -LiteralPath $file.Path)) {
                $removed++
                $freed += $file.Size
                Write-IRTLog ('Gone during cleanup: {0}' -f $file.Path) 'WARN'
            }
            else {
                $failures++
                Write-IRTLog ('Cleanup failed: {0} | {1}' -f $file.Path, $_.Exception.Message) 'WARN'
            }
        }
    }

    $after       = Get-DumpInventory -Config $config
    $remaining   = @($after.Files | Where-Object { $_.Written -lt $cutoff })
    $remainBytes = 0.0
    foreach ($file in $after.Files) { $remainBytes += $file.Size }

    $summary = 'Removed={0}; FreedMB={1}; RemainingMB={2}; Failures={3}' -f $removed, (Format-SizeMB $freed), (Format-SizeMB $remainBytes), $failures
    if ($failures -gt 0 -or $remaining.Count -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: CleanupFailed | $($_.Exception.Message)" }
