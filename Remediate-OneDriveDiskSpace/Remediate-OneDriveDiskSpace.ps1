<#
.SYNOPSIS
  Remediation script for low disk space that OneDrive keeps occupied.

.DESCRIPTION
  Converts locally available OneDrive files to online-only with the Files On-Demand attribute, largest files first, until the target free space is reached. Verifies every file and the free space after the change. Exits 0 if the drive is above the threshold or files were freed, 1 if nothing could be freed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinFreeSpaceGB    = 15
$TargetFreeSpaceGB = 20
$IncludePinned     = $false
$MaxFilesPerRun    = 3000
$VerifyWaitSec     = 15

$PackageName = 'OneDriveDiskSpace'
$Phase       = 'Remediate'
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

function Test-OnlineOnly { param($Item)
    $attrs = [int]$Item.Attributes
    (($attrs -band 0x400000) -ne 0) -or (($attrs -band 0x1000) -ne 0)
}

function Get-CandidateFile {
    param([string]$Root)
    $list = Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { (Test-OnlineOnly $_) -eq $false }
    if (-not $IncludePinned) { $list = $list | Where-Object { ([int]$_.Attributes -band 0x80000) -eq 0 } }
    $list | Where-Object { $_.FullName -notlike '*\OneDriveTemp\*' } | Sort-Object -Property Length -Descending
}

try {
    $root = Get-OneDriveRoot
    if (-not $root) { Exit-Script 0 'NotApplicable | OneDriveFolder=NotFound' }

    $disk = Get-SystemDisk
    if ($disk.FreeGB -ge $MinFreeSpaceGB) { Exit-Script 0 "NoAction | FreeGB=$($disk.FreeGB); ThresholdGB=$MinFreeSpaceGB" }

    $fod = Test-FilesOnDemand
    if ($fod -ne 'Enabled') { Exit-Script 0 "NotApplicable | FilesOnDemand=$fod; FreeGB=$($disk.FreeGB)" }

    $neededBytes = [int64](($TargetFreeSpaceGB - $disk.FreeGB) * 1GB)
    if ($neededBytes -lt 0) { $neededBytes = 0 }

    $candidates = @(Get-CandidateFile -Root $root)
    if ($candidates.Count -eq 0) { Exit-Script 0 "NoAction | FreeGB=$($disk.FreeGB); Candidates=0" }
    Write-IRTLog "Candidates=$($candidates.Count); NeededMB=$([math]::Round($neededBytes / 1MB))"

    $done = 0; $failed = 0; $processed = 0
    foreach ($file in $candidates) {
        if ($processed -ge $MaxFilesPerRun) { break }
        if ($done -ge $neededBytes) { break }
        $processed++
        & attrib.exe +U -P $file.FullName | Out-Null
        $code = $LASTEXITCODE
        $current = Get-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        if ($current -and (Test-OnlineOnly $current)) {
            $done += $file.Length
        }
        else {
            $failed++
            Write-IRTLog "Unpin failed ($code): $($file.FullName)" 'WARN'
        }
    }

    $waited = 0
    while ($waited -lt $VerifyWaitSec) {
        Start-Sleep -Seconds 3
        $waited += 3
        $after = Get-SystemDisk
        if ($after.FreeGB -ge $TargetFreeSpaceGB) { break }
        if ($after.FreeGB -gt $disk.FreeGB) { break }
    }
    $after = Get-SystemDisk
    $freedGB = [math]::Round($after.FreeGB - $disk.FreeGB, 2)

    $unpinnedMB = [math]::Round($done / 1MB, 0)
    $summary = "FreeGB=$($after.FreeGB); BeforeGB=$($disk.FreeGB); FreedGB=$freedGB; UnpinnedMB=$unpinnedMB; UnpinnedFiles=$processed; Failed=$failed"
    if ($done -gt 0 -and $after.FreeGB -ge $MinFreeSpaceGB) { Exit-Script 0 "Fixed | $summary" }
    if ($done -gt 0) { Exit-Script 1 "Partial | $summary" }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
