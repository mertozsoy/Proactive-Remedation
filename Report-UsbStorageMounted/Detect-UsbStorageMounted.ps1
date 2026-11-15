<#
.SYNOPSIS
  Detection script for USB storage that is present while device control should block it.

.DESCRIPTION
  Reads the removable storage policy values and the USBSTOR service start type. Lists every USB disk drive that is currently present with its volumes and drive letters. Exits 1 if USB storage is found while a block is configured, 0 otherwise. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RemovableStoragePolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
$UsbStorServiceKey        = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
$ClassDenyValueNames      = @('Deny_Read', 'Deny_Write', 'Deny_Execute')
$MaxListedDevices         = 5
$IncludeVolumeLetters     = $true
$MaxModelLength           = 40

$PackageName = 'UsbStorageMounted'
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

function Get-RegistryDword { param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $value = $item.$Name
    if ($null -eq $value) { return $null }
    return [int]$value
}

function Get-BlockState {
    $denyAll      = Get-RegistryDword -Path $RemovableStoragePolicyKey -Name 'Deny_All'
    $usbStorStart = Get-RegistryDword -Path $UsbStorServiceKey -Name 'Start'
    $classDeny    = 0

    if (Test-Path -LiteralPath $RemovableStoragePolicyKey) {
        $policyKeys = @(Get-ChildItem -LiteralPath $RemovableStoragePolicyKey -Recurse -ErrorAction SilentlyContinue)
        foreach ($policyKey in $policyKeys) {
            foreach ($valueName in $ClassDenyValueNames) {
                if ((Get-RegistryDword -Path $policyKey.PSPath -Name $valueName) -eq 1) { $classDeny++; break }
            }
        }
    }

    $blocked = $false
    $label   = 'None'
    if ($denyAll -eq 1) { $blocked = $true; $label = 'DenyAll' }
    elseif ($classDeny -gt 0) { $blocked = $true; $label = 'Class' }
    elseif ($usbStorStart -eq 4) { $blocked = $true; $label = 'UsbStorDisabled' }

    [pscustomobject]@{
        Label        = $label
        DenyAll      = $denyAll
        ClassDeny    = $classDeny
        UsbStorStart = $usbStorStart
        Blocked      = $blocked
    }
}

function Get-UsbStorageDevice {
    $disks = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | Where-Object {
        $_.InterfaceType -eq 'USB' -or "$($_.PNPDeviceID)" -like 'USBSTOR*'
    })

    foreach ($disk in $disks) {
        $letters = New-Object System.Collections.Generic.List[string]
        $volumes = 0
        try {
            $partitions = @(Get-CimAssociatedInstance -InputObject $disk -Association Win32_DiskDriveToDiskPartition -ErrorAction Stop)
            foreach ($partition in $partitions) {
                $logicalDisks = @(Get-CimAssociatedInstance -InputObject $partition -Association Win32_LogicalDiskToPartition -ErrorAction Stop)
                foreach ($logicalDisk in $logicalDisks) {
                    $volumes++
                    $deviceId = "$($logicalDisk.DeviceID)".Trim()
                    if ($deviceId -and -not $letters.Contains($deviceId)) { $letters.Add($deviceId) }
                }
            }
        }
        catch { Write-IRTLog "Volume lookup failed for $($disk.Model): $($_.Exception.Message)" -Level 'WARN' }

        $model = "$($disk.Model)".Trim() -replace ',', ' '
        if (-not $model) { $model = 'Unknown' }
        if ($model.Length -gt $MaxModelLength) { $model = $model.Substring(0, $MaxModelLength) }
        $sizeGB = 0
        if ($disk.Size) { $sizeGB = [math]::Round([double]$disk.Size / 1GB) }

        [pscustomobject]@{
            Model   = $model
            SizeGB  = $sizeGB
            Volumes = $volumes
            Letters = @($letters)
        }
    }
}

try {
    $block = Get-BlockState
    $devices = @(Get-UsbStorageDevice)
    $volumeCount = 0
    foreach ($device in $devices) { $volumeCount += $device.Volumes }

    foreach ($device in $devices) {
        Write-IRTLog ('USB storage | {0} | {1} GB | Volumes={2} | Letters={3}' -f $device.Model, $device.SizeGB, $device.Volumes, ($device.Letters -join ' '))
    }

    $listed = New-Object System.Collections.Generic.List[string]
    foreach ($device in ($devices | Select-Object -First $MaxListedDevices)) {
        $text = '{0}({1}GB' -f $device.Model, $device.SizeGB
        if ($IncludeVolumeLetters -and $device.Letters.Count -gt 0) { $text += ',' + ($device.Letters -join ' ') }
        $text += ')'
        $listed.Add($text)
    }
    $more = [math]::Max(0, $devices.Count - $MaxListedDevices)
    $deviceText = 'None'
    if ($listed.Count -gt 0) {
        $deviceText = $listed -join ','
        if ($more -gt 0) { $deviceText += ",+$more" }
    }

    $denyAllText  = 'None'
    if ($null -ne $block.DenyAll) { $denyAllText = $block.DenyAll }
    $usbStorText  = 'Unknown'
    if ($null -ne $block.UsbStorStart) { $usbStorText = $block.UsbStorStart }

    $summary = 'Block={0}; DenyAll={1}; ClassDeny={2}; UsbStorStart={3}; Devices={4}; Volumes={5}; Models={6}' -f $block.Label, $denyAllText, $block.ClassDeny, $usbStorText, $devices.Count, $volumeCount, $deviceText

    if (-not $block.Blocked) { Exit-Script 0 "NoBlockPolicy | $summary" }
    if ($devices.Count -gt 0) { Exit-Script 1 "UsbStorageMounted ($($devices.Count)) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
