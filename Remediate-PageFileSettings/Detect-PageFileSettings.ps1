<#
.SYNOPSIS
  Detection script for a page file that is no longer system managed.

.DESCRIPTION
  Reads automatic page file management from Win32_ComputerSystem, the configured page files from Win32_PageFileSetting and the PagingFiles registry value. Exits 1 if automatic management is off or no page file is configured, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumFreeSpaceGB = 2

$PackageName = 'PageFileSettings'
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

try {
    if ($MinimumFreeSpaceGB -lt 1) { throw 'MinimumFreeSpaceGB must be at least 1.' }

    $state = Get-PageFileState
    $summary = "Mode=$($state.Mode); PageFiles=$($state.Settings); ConfiguredMB=$($state.ConfiguredMB); AllocatedMB=$($state.AllocatedMB); RamMB=$($state.RamMB); Dump=$($state.Dump); FreeGB=$($state.FreeGB)"
    if ($state.TempPageFile) { $summary += '; TempPageFile=True' }
    Write-IRTLog "Measured | $summary"

    if ($state.Mode -ne 'SystemManaged') { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
