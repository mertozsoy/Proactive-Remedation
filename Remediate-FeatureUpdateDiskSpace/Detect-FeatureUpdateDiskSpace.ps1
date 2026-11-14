<#
.SYNOPSIS
  Detection script for insufficient system drive space before a feature update.

.DESCRIPTION
  Compares free bytes on the Windows system drive with an administrator-defined target.
  Exits 1 below the target or on error, 0 when healthy or not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumFreeGB = 30

$PackageName = 'FeatureUpdateDiskSpace'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumFreeGB -le 0 -or $MinimumFreeGB -gt 1024) { throw 'Invalid threshold' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 19041) {
        Exit-Script 0 'NotApplicable | Reason=RequiresWindows10Or11Client'
    }
    $drive = [string]$os.SystemDrive
    if ($drive -notmatch '^[A-Za-z]:$') { throw 'Invalid system drive' }
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction Stop
    if ($null -eq $disk -or $disk.DriveType -ne 3 -or $null -eq $disk.FreeSpace) { throw 'System disk unavailable' }
    $freeBytes = [double]$disk.FreeSpace
    $freeGB = [math]::Round($freeBytes / 1GB, 2)
    if ($freeBytes -lt ($MinimumFreeGB * 1GB)) {
        Exit-Script 1 "Drift | Drive=$drive; FreeGB=$freeGB; RequiredGB=$MinimumFreeGB"
    }
    Exit-Script 0 "Healthy | Drive=$drive; FreeGB=$freeGB; RequiredGB=$MinimumFreeGB"
}
catch { Exit-Script 1 "Error: CheckFailed | Type=$($_.Exception.GetType().Name); HResult=$($_.Exception.HResult)" }
