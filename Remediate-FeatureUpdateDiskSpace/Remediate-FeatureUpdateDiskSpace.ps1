<#
.SYNOPSIS
  Remediation script for insufficient system drive space before a feature update.

.DESCRIPTION
  Clears unpinned Delivery Optimization cache and runs supported component cleanup only
  when free space is below the configured target. Never deletes user files or reboots.
  Exits 0 only when the target is met or the device is not applicable; otherwise exits 1.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumFreeGB = 30
$ClearDeliveryOptimizationCache = $true
$RunComponentCleanup = $true
$DismWaitSeconds = 600

$PackageName = 'FeatureUpdateDiskSpace'
$Phase = 'Remediate'
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
function Get-SystemFreeBytes { param([string]$Drive)
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$Drive'" -ErrorAction Stop
    if ($null -eq $disk -or $disk.DriveType -ne 3 -or $null -eq $disk.FreeSpace) { throw 'System disk unavailable' }
    return [double]$disk.FreeSpace
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumFreeGB -le 0 -or $MinimumFreeGB -gt 1024) { throw 'Invalid threshold' }
    if ($DismWaitSeconds -lt 1 -or $DismWaitSeconds -gt 900) { throw 'Invalid wait time' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 19041) {
        Exit-Script 0 'NotApplicable | Reason=RequiresWindows10Or11Client'
    }
    if (-not [Environment]::Is64BitProcess) { throw 'Requires 64-bit PowerShell' }
    $drive = [string]$os.SystemDrive
    if ($drive -notmatch '^[A-Za-z]:$') { throw 'Invalid system drive' }
    $requiredBytes = $MinimumFreeGB * 1GB
    $beforeBytes = Get-SystemFreeBytes -Drive $drive
    if ($beforeBytes -ge $requiredBytes) {
        Exit-Script 0 "Healthy | Drive=$drive; FreeGB=$([math]::Round($beforeBytes / 1GB, 2)); RequiredGB=$MinimumFreeGB"
    }
    $busy = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='dism.exe' OR Name='DismHost.exe' OR Name='TiWorker.exe' OR Name='setuphost.exe' OR Name='setupprep.exe'" -ErrorAction Stop)
    if ($busy.Count -gt 0) { Exit-Script 1 'Deferred | Reason=ServicingOrSetupRunning; Retry=NextSchedule' }
    $steps = @()
    if ($ClearDeliveryOptimizationCache) {
        $statusCommand = Get-Command -Name Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue
        $deleteCommand = Get-Command -Name Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue
        if ($null -eq $statusCommand -or $null -eq $deleteCommand) {
            $steps += 'DO=Unavailable'
        }
        else {
            try {
                $jobs = @(Get-DeliveryOptimizationStatus -ErrorAction Stop)
                $pending = @($jobs | Where-Object { $_.Status -eq 'Downloading' -or $_.Status -eq 'Paused' })
                if ($pending.Count -gt 0) {
                    Exit-Script 1 'Deferred | Reason=DeliveryOptimizationDownload; Retry=NextSchedule'
                }
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null
                $steps += 'DO=Cleared'
            }
            catch {
                $steps += 'DO=Failed'
                Write-IRTLog "DeliveryOptimizationFailed | Type=$($_.Exception.GetType().Name); HResult=$($_.Exception.HResult)" 'WARN'
            }
        }
    }
    $afterBytes = Get-SystemFreeBytes -Drive $drive
    if ($afterBytes -lt $requiredBytes -and $RunComponentCleanup) {
        $busy = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='dism.exe' OR Name='DismHost.exe' OR Name='TiWorker.exe' OR Name='setuphost.exe' OR Name='setupprep.exe'" -ErrorAction Stop)
        if ($busy.Count -gt 0) { Exit-Script 1 'Deferred | Reason=ServicingOrSetupRunning; Retry=NextSchedule' }
        $dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
        $arguments = @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart', '/Quiet')
        $process = Start-Process -FilePath $dismPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $process.WaitForExit($DismWaitSeconds * 1000)) {
            $afterBytes = Get-SystemFreeBytes -Drive $drive
            Exit-Script 1 "Pending | Reason=ComponentCleanupRunning; FreeGB=$([math]::Round($afterBytes / 1GB, 2)); RequiredGB=$MinimumFreeGB; Retry=NextSchedule"
        }
        $process.Refresh()
        $dismCode = $process.ExitCode
        $steps += "DISM=$dismCode"
        Write-IRTLog "ComponentCleanup | ExitCode=$dismCode"
        if ($dismCode -ne 0) {
            $afterBytes = Get-SystemFreeBytes -Drive $drive
            Exit-Script 1 "Failed | Reason=ComponentCleanupExitCode; DISM=$dismCode; FreeGB=$([math]::Round($afterBytes / 1GB, 2)); RequiredGB=$MinimumFreeGB"
        }
    }
    $afterBytes = Get-SystemFreeBytes -Drive $drive
    $freeGB = [math]::Round($afterBytes / 1GB, 2)
    $deltaGB = [math]::Round(($afterBytes - $beforeBytes) / 1GB, 2)
    $actions = $steps -join ','
    if (-not $actions) { $actions = 'None' }
    if ($afterBytes -lt $requiredBytes) {
        Exit-Script 1 "Failed | FreeGB=$freeGB; RequiredGB=$MinimumFreeGB; DeltaGB=$deltaGB; Actions=$actions; Reason=SpaceStillLow"
    }
    Exit-Script 0 "Fixed | FreeGB=$freeGB; RequiredGB=$MinimumFreeGB; DeltaGB=$deltaGB; Actions=$actions"
}
catch { Exit-Script 1 "Error: CleanupFailed | Type=$($_.Exception.GetType().Name); HResult=$($_.Exception.HResult)" }
