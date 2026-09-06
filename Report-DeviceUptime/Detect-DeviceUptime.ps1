<#
.SYNOPSIS
    Intune Remediations detection script for Windows uptime reporting.

.DESCRIPTION
    Collects the OS kernel boot time from Win32_OperatingSystem.LastBootUpTime,
    calculates uptime, and writes a compact Task Manager-like single-line output for Intune.

.NOTES
    Version: 1.0
    Run As: System
    PowerShell: Windows PowerShell 5.1 compatible
#>

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8

function ConvertTo-LocalDateTime {
    param([Parameter(Mandatory = $true)]$Value)

    if ($Value -is [datetime]) { return $Value }
    return [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $lastBootLocal = ConvertTo-LocalDateTime -Value $os.LastBootUpTime
    $nowLocal = Get-Date
    $uptime = New-TimeSpan -Start $lastBootLocal -End $nowLocal
    $uptimeText = "{0}:{1:00}:{2:00}:{3:00}" -f [int][math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes, $uptime.Seconds

    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::WriteLine("DeviceName=$env:COMPUTERNAME; Uptime=$uptimeText")

    exit 0
}
catch {
    [Console]::WriteLine("DeviceName=$env:COMPUTERNAME; Uptime=ERROR; Error=$($_.Exception.Message)")
    exit 1
}
