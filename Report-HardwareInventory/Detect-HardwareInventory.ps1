<#
.SYNOPSIS
  Hardware and firmware inventory script.

.DESCRIPTION
  Writes a short hardware and firmware summary as one line to the Intune output. Always exits 0.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'HardwareInventory'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

try {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os   = Get-CimInstance Win32_OperatingSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $tpm = $null
    try { $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop } catch { }
    $sb = try { Confirm-SecureBootUEFI -ErrorAction Stop } catch { 'Unsupported' }

    $sysDisk = $null
    try {
        $part = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
        $pd   = Get-PhysicalDisk | Where-Object DeviceId -eq ([string]$part.DiskNumber) | Select-Object -First 1
        $vol  = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':'))
        $sysDisk = '{0}/{1}GB/free {2}GB' -f $pd.MediaType, [math]::Round($vol.Size / 1GB), [math]::Round($vol.SizeRemaining / 1GB)
    } catch { }

    $battery = $null
    try {
        $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
        $full   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
        if ($design -gt 0) { $battery = '{0}%' -f [math]::Round(($full / $design) * 100) }
    } catch { }

    $inv = [ordered]@{
        Make      = $cs.Manufacturer
        Model     = $cs.Model
        Serial    = $bios.SerialNumber
        BIOS      = $bios.SMBIOSBIOSVersion
        BIOSDate  = $(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') })
        TPM       = $(if ($tpm) { ($tpm.SpecVersion -split ',')[0] } else { 'None' })
        SecureBoot= $sb
        CPU       = ($cpu.Name -replace '\s+', ' ').Trim()
        RAMGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB)
        OS        = $os.Caption -replace 'Microsoft ', ''
        Version   = $cv.DisplayVersion
        Build     = '{0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR
        SysDisk   = $sysDisk
        Battery   = $battery
        LastBoot  = $os.LastBootUpTime.ToString('yyyy-MM-dd')
    }
    Exit-Script 0 ($inv | ConvertTo-Json -Compress)
}
catch { Exit-Script 0 "{`"Error`":`"$($_.Exception.Message -replace '"', "'")`"}" }
