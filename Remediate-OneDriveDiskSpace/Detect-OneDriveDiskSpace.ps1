<#
.SYNOPSIS
  Detection script for low disk space that OneDrive keeps occupied.

.DESCRIPTION
  Reads the free space on the system drive and measures how much OneDrive data is stored locally. Exits 1 if free space is below the threshold and unpinning can give a meaningful amount back, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinFreeSpaceGB = 15
$MinReclaimGB   = 2
$MaxScanFiles   = 60000

$PackageName = 'OneDriveDiskSpace'
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

function Get-OneDriveRoot {
    foreach ($candidate in @($env:OneDriveCommercial, $env:OneDrive)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) { return $candidate }
    }
    $found = Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OneDrive*' } | Sort-Object Name | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Test-FilesOnDemand {
    $policy = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' -Name FilesOnDemandEnabled -ErrorAction SilentlyContinue).FilesOnDemandEnabled
    if ($null -ne $policy -and [int]$policy -eq 0) { return 'DisabledByPolicy' }
    $start = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\CldFlt' -Name Start -ErrorAction SilentlyContinue).Start
    if ($null -eq $start) { return 'DriverMissing' }
    if ([int]$start -ne 2) { return 'DriverStopped' }
    return 'Enabled'
}

function Get-SystemDisk {
    $letter = $env:SystemDrive
    if (-not $letter) { $letter = 'C:' }
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$letter'" -ErrorAction Stop
    [pscustomobject]@{ FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2); TotalGB = [math]::Round($disk.Size / 1GB, 2) }
}

function Get-LocalCopyStats {
    param([string]$Root)
    $stats = @{ Files = 0; Bytes = [int64]0; PinnedBytes = [int64]0; PinnedFiles = 0 }
    $items = Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Select-Object -First $MaxScanFiles
    foreach ($item in $items) {
        if ($item.FullName -like '*\OneDriveTemp\*') { continue }
        $attrs = [int]$item.Attributes
        $onlineOnly = (($attrs -band 0x400000) -ne 0) -or (($attrs -band 0x1000) -ne 0)
        if ($onlineOnly) { continue }
        $pinned = ($attrs -band 0x80000) -ne 0
        if ($pinned) {
            $stats.PinnedFiles++
            $stats.PinnedBytes += $item.Length
        }
        else {
            $stats.Files++
            $stats.Bytes += $item.Length
        }
    }
    $stats
}

try {
    $root = Get-OneDriveRoot
    if (-not $root) { Exit-Script 0 'NotApplicable | OneDriveFolder=NotFound' }

    $disk = Get-SystemDisk
    if ($disk.FreeGB -ge $MinFreeSpaceGB) { Exit-Script 0 "Healthy | FreeGB=$($disk.FreeGB); ThresholdGB=$MinFreeSpaceGB" }

    $fod = Test-FilesOnDemand
    if ($fod -ne 'Enabled') { Exit-Script 0 "NotApplicable | FilesOnDemand=$fod; FreeGB=$($disk.FreeGB)" }

    $stats = Get-LocalCopyStats -Root $root
    $localGB = [math]::Round(($stats.Bytes + $stats.PinnedBytes) / 1GB, 2)
    $reclaimGB = [math]::Round($stats.Bytes / 1GB, 2)
    $pinnedGB = [math]::Round($stats.PinnedBytes / 1GB, 2)

    if ($reclaimGB -lt $MinReclaimGB) {
        Exit-Script 0 "LowSpaceNoGain | FreeGB=$($disk.FreeGB); OneDriveLocalGB=$localGB; ReclaimableGB=$reclaimGB; PinnedGB=$pinnedGB"
    }
    Exit-Script 1 "Drift | FreeGB=$($disk.FreeGB); ThresholdGB=$MinFreeSpaceGB; OneDriveLocalGB=$localGB; ReclaimableGB=$reclaimGB; Files=$($stats.Files); PinnedGB=$pinnedGB"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
