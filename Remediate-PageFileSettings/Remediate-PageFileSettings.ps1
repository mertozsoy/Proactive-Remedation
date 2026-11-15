<#
.SYNOPSIS
  Remediation script that restores a system managed page file.

.DESCRIPTION
  Backs up the memory management registry key, turns automatic page file management back on and optionally moves a disabled memory dump to the automatic dump type. Exits 0 when the setting is applied and read back, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SetAutomaticMemoryDump = $false
$BackupRegistry         = $true
$MinimumFreeSpaceGB     = 2

$PackageName = 'PageFileSettings'
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

$MemoryKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$CrashKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
$DumpTypes = @{ 0 = 'None'; 1 = 'Complete'; 2 = 'Kernel'; 3 = 'Small'; 7 = 'Automatic' }

function Get-FreeSpaceGB {
    $drive = $env:SystemDrive
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction Stop
    if ($null -eq $disk) { return 0 }
    [math]::Round([double]$disk.FreeSpace / 1GB, 1)
}

function Get-DumpType {
    $value = $null
    if (Test-Path -LiteralPath $CrashKey) {
        $value = (Get-ItemProperty -LiteralPath $CrashKey -Name CrashDumpEnabled -ErrorAction SilentlyContinue).CrashDumpEnabled
    }
    if ($null -eq $value) { return 'Unset' }
    $number = [int]$value
    if ($DumpTypes.ContainsKey($number)) { return $DumpTypes[$number] }
    "Type$number"
}

function Get-PageFileState {
    $system   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $settings = @(Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue)
    $usage    = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue)

    $entries = @()
    if (Test-Path -LiteralPath $MemoryKey) {
        $raw = (Get-ItemProperty -LiteralPath $MemoryKey -Name PagingFiles -ErrorAction SilentlyContinue).PagingFiles
        if ($null -ne $raw) { $entries = @($raw | Where-Object { $_ }) }
    }

    $auto = [bool]$system.AutomaticManagedPagefile
    $mode = 'Fixed'
    if ($auto) { $mode = 'SystemManaged' }
    elseif ($settings.Count -eq 0 -and $entries.Count -eq 0) { $mode = 'Disabled' }

    $configuredMB = 0
    foreach ($item in $settings) { $configuredMB += [int]$item.MaximumSize }
    $allocatedMB = 0
    $tempPageFile = $false
    foreach ($item in $usage) {
        $allocatedMB += [int]$item.AllocatedBaseSize
        if ([bool]$item.TempPageFile) { $tempPageFile = $true }
    }

    [pscustomobject]@{
        Mode         = $mode
        AutoManaged  = $auto
        Settings     = $settings.Count
        Entries      = $entries.Count
        ConfiguredMB = $configuredMB
        AllocatedMB  = $allocatedMB
        TempPageFile = $tempPageFile
        RamMB        = [math]::Round([double]$system.TotalPhysicalMemory / 1MB)
        Dump         = Get-DumpType
        FreeGB       = Get-FreeSpaceGB
    }
}

function Save-MemoryKeyBackup {
    $backupDir = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
    }
    $file = Join-Path $backupDir ('MemoryManagement_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' $file /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { return $null }
    $file
}

try {
    if ($MinimumFreeSpaceGB -lt 1) { throw 'MinimumFreeSpaceGB must be at least 1.' }

    $state = Get-PageFileState
    $previous = "Previous=$($state.Mode); PreviousMB=$($state.ConfiguredMB)"
    if ($state.Mode -eq 'SystemManaged') {
        Exit-Script 0 "Healthy | Mode=SystemManaged; RamMB=$($state.RamMB); Dump=$($state.Dump); FreeGB=$($state.FreeGB)"
    }

    if ($state.FreeGB -lt $MinimumFreeSpaceGB) {
        Exit-Script 1 "Failed | Reason=LowFreeSpace; FreeGB=$($state.FreeGB); RequiredGB=$MinimumFreeSpaceGB; $previous"
    }

    $backupFile = 'Disabled'
    if ($BackupRegistry) {
        $backupFile = Save-MemoryKeyBackup
        if (-not $backupFile) { Exit-Script 1 "Failed | Reason=BackupFailed; $previous" }
        Write-IRTLog "Backup saved: $backupFile"
    }

    $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $system.AutomaticManagedPagefile = $true
    $null = Set-CimInstance -InputObject $system -PassThru -ErrorAction Stop
    Write-IRTLog 'AutomaticManagedPagefile set to True'

    if ($SetAutomaticMemoryDump) {
        $dumpValue = (Get-ItemProperty -LiteralPath $CrashKey -Name CrashDumpEnabled -ErrorAction SilentlyContinue).CrashDumpEnabled
        if ($null -ne $dumpValue -and [int]$dumpValue -eq 0) {
            Set-ItemProperty -LiteralPath $CrashKey -Name CrashDumpEnabled -Value 7 -Type DWord -ErrorAction Stop
            Write-IRTLog 'CrashDumpEnabled set to 7 (Automatic)'
        }
    }

    $after = Get-PageFileState
    $summary = "$previous; Mode=$($after.Mode); RamMB=$($after.RamMB); Dump=$($after.Dump); Reboot=Required"
    if ($after.Mode -ne 'SystemManaged') { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary; Backup=$backupFile"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
