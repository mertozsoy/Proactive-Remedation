<#
.SYNOPSIS
  Detection script for kernel crash dump files left on the system drive.

.DESCRIPTION
  Reads the dump paths from CrashControl and sizes MEMORY.DMP, the minidump folder and LiveKernelReports. Exits 1 when dump files older than MinimumAgeDays reach ThresholdMB, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 7
$ThresholdMB    = 500

$PackageName = 'CrashDumps'
$Phase       = 'Detect'
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
    $config    = Get-DumpConfiguration
    $inventory = Get-DumpInventory -Config $config
    if ($inventory.Roots -eq 0) { Exit-Script 0 'NotApplicable | DumpPaths=None' }

    $cutoff   = (Get-Date).AddDays(-$MinimumAgeDays)
    $eligible = @($inventory.Files | Where-Object { $_.Written -lt $cutoff })
    $totalBytes = 0.0
    foreach ($file in $inventory.Files) { $totalBytes += $file.Size }
    $cleanBytes = 0.0
    foreach ($file in $eligible) { $cleanBytes += $file.Size }

    Write-IRTLog ('Roots={0} Files={1} Eligible={2} DumpType={3} AlwaysKeep={4}' -f $inventory.Roots, $inventory.Files.Count, $eligible.Count, $config.DumpType, $config.AlwaysKeep)
    foreach ($file in $eligible) { Write-IRTLog ('Eligible {0} MB {1}' -f (Format-SizeMB $file.Size), $file.Path) }

    $summary = 'Files={0}; TotalMB={1}; CleanableMB={2}; Age={3}d; DumpType={4}' -f $inventory.Files.Count, (Format-SizeMB $totalBytes), (Format-SizeMB $cleanBytes), $MinimumAgeDays, $config.DumpType
    if ((Format-SizeMB $cleanBytes) -ge $ThresholdMB) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: InspectionFailed | $($_.Exception.Message)" }
