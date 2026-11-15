<#
.SYNOPSIS
  Detection script for a hibernation file kept on desktop devices.

.DESCRIPTION
  Checks the device type, the hibernation state and the size of hiberfil.sys. Exits 1 if a desktop keeps a hibernation file that has to be removed or shrunk, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$HibernateMode             = 'Remove'
$ReducedSizeCeilingPercent = 25
$DesktopOnly               = $true
$PowerKey                  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
$HiberfilPath              = $env:SystemDrive + '\hiberfil.sys'

$PackageName = 'DesktopHibernation'
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
function Test-DesktopComputer {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ([int]$computer.PCSystemType -eq 2) { return $false }
    $portableChassis = @(8, 9, 10, 11, 14, 30, 31, 32)
    foreach ($enclosure in @(Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue)) {
        foreach ($chassis in @($enclosure.ChassisTypes)) {
            if ($portableChassis -contains [int]$chassis) { return $false }
        }
    }
    if (@(Get-CimInstance -ClassName Win32_PortableBattery -ErrorAction SilentlyContinue).Count -gt 0) { return $false }
    if (@(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0) { return $false }
    return $true
}
function Get-HibernationSetting {
    param([string]$Name)
    $value = -1
    $power = Get-ItemProperty -LiteralPath $PowerKey -ErrorAction SilentlyContinue
    if ($null -ne $power -and $null -ne $power.$Name) { $value = [int]$power.$Name }
    $value
}

try {
    if ($HibernateMode -ne 'Remove' -and $HibernateMode -ne 'Reduce') { Exit-Script 1 'Failed | Reason=InvalidHibernateMode' }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=ServerOS' }
    if ($DesktopOnly -and -not (Test-DesktopComputer)) { Exit-Script 0 'NotApplicable | Reason=NotADesktop' }

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $ramMB = [int64][math]::Floor($computer.TotalPhysicalMemory / 1MB)

    $hibernateEnabled = Get-HibernationSetting -Name 'HibernateEnabled'
    $sizePercent = Get-HibernationSetting -Name 'HiberFileSizePercent'

    $file = Get-Item -LiteralPath $HiberfilPath -Force -ErrorAction SilentlyContinue
    $fileMB = 0
    if ($null -ne $file) { $fileMB = [int64][math]::Floor($file.Length / 1MB) }

    $drift = $false
    $ceilingMB = 0
    if ($HibernateMode -eq 'Reduce') {
        if ($null -ne $file) {
            $ceilingMB = [int64][math]::Floor($ramMB * $ReducedSizeCeilingPercent / 100)
            if ($fileMB -gt $ceilingMB) { $drift = $true }
        }
    }
    else {
        if ($null -ne $file -or $hibernateEnabled -eq 1) { $drift = $true }
    }

    $summary = 'Mode={0}; HiberfilMB={1}; RamMB={2}; HibernateEnabled={3}; SizePercent={4}; CeilingMB={5}' -f $HibernateMode, $fileMB, $ramMB, $hibernateEnabled, $sizePercent, $ceilingMB
    if ($drift) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
