<#
.SYNOPSIS
  Remediation script that removes or shrinks hiberfil.sys on desktop devices.

.DESCRIPTION
  Disables hibernation on a desktop and deletes the hibernation file, or shrinks the file to a reduced hiberfile when the mode is set to Reduce. Exits 0 when the file is gone or small enough, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$HibernateMode             = 'Remove'
$ReducedSizeCeilingPercent = 25
$DesktopOnly               = $true
$RemoveOrphanedFile        = $true
$PowerKey                  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
$HiberfilPath              = $env:SystemDrive + '\hiberfil.sys'
$PowerCfgPath              = Join-Path $env:SystemRoot 'System32\powercfg.exe'

$PackageName = 'DesktopHibernation'
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
function Get-HiberfilSizeMB {
    $file = Get-Item -LiteralPath $HiberfilPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $file) { return 0 }
    [int64][math]::Floor($file.Length / 1MB)
}
function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $process = Start-Process -FilePath $PowerCfgPath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    Write-IRTLog ("powercfg {0} -> exit {1}" -f ($Arguments -join ' '), $process.ExitCode)
    [int]$process.ExitCode
}

try {
    if ($HibernateMode -ne 'Remove' -and $HibernateMode -ne 'Reduce') { Exit-Script 1 'Failed | Reason=InvalidHibernateMode' }
    if (-not (Test-Path -LiteralPath $PowerCfgPath)) { Exit-Script 1 'Failed | Reason=PowerCfgMissing' }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=ServerOS' }
    if ($DesktopOnly -and -not (Test-DesktopComputer)) { Exit-Script 0 'NotApplicable | Reason=NotADesktop' }

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $ramMB = [int64][math]::Floor($computer.TotalPhysicalMemory / 1MB)
    $beforeMB = Get-HiberfilSizeMB

    if ($HibernateMode -eq 'Reduce') {
        if ($beforeMB -eq 0) { Exit-Script 0 'NotApplicable | HiberfilMB=0' }

        $sizeExit = Invoke-PowerCfg @('/hibernate', '/size', '0')
        $typeExit = Invoke-PowerCfg @('/hibernate', '/type', 'reduced')
        $afterMB = Get-HiberfilSizeMB
        $ceilingMB = [int64][math]::Floor($ramMB * $ReducedSizeCeilingPercent / 100)

        if ($sizeExit -ne 0 -or $typeExit -ne 0) {
            Exit-Script 1 "Failed | PowerCfgSizeExit=$sizeExit; PowerCfgTypeExit=$typeExit; HiberfilMB=$afterMB"
        }
        if ($afterMB -eq 0) { Exit-Script 1 'Failed | HiberfilMB=0; Reason=FileDidNotComeBack' }
        if ($afterMB -gt $ceilingMB) { Exit-Script 1 "Failed | HiberfilMB=$afterMB; CeilingMB=$ceilingMB" }
        Exit-Script 0 "Fixed | HiberfilMB=$afterMB; BeforeMB=$beforeMB; CeilingMB=$ceilingMB; Type=Reduced"
    }

    $offExit = Invoke-PowerCfg @('/hibernate', 'off')
    $afterMB = Get-HiberfilSizeMB
    for ($attempt = 0; $attempt -lt 3 -and $afterMB -gt 0; $attempt++) {
        Start-Sleep -Seconds 2
        $afterMB = Get-HiberfilSizeMB
    }

    if ($afterMB -gt 0 -and $RemoveOrphanedFile) {
        try {
            Remove-Item -LiteralPath $HiberfilPath -Force -ErrorAction Stop
            Write-IRTLog 'Orphaned hiberfil.sys removed'
        }
        catch { Write-IRTLog "Orphaned file could not be removed: $($_.Exception.Message)" 'WARN' }
        $afterMB = Get-HiberfilSizeMB
    }

    $hibernateEnabled = Get-HibernationSetting -Name 'HibernateEnabled'
    if ($afterMB -gt 0 -or $hibernateEnabled -eq 1) {
        Exit-Script 1 "Failed | HiberfilMB=$afterMB; HibernateEnabled=$hibernateEnabled; PowerCfgExit=$offExit"
    }
    Exit-Script 0 "Fixed | HiberfilMB=0; ReclaimedMB=$beforeMB; HibernateEnabled=$hibernateEnabled"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
