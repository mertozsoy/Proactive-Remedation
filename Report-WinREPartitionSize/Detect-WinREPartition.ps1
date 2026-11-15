<#
.SYNOPSIS
  Detection script for a Windows Recovery Environment partition that is too small for servicing.

.DESCRIPTION
  Finds the partition that holds Windows RE from the reagentc configuration and from
  the GPT recovery partition type. Reads the partition size and free space. Exits 1
  when free space is below the 250 MB that Windows needs to service the WinRE image,
  or when the free space cannot be read. Exits 0 when there is enough room or WinRE
  is not configured. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumFreeSpaceMB = 250
$RecoveryGptType = 'de94bba4-06d1-4d40-a16a-bfd50179d6ac'
$WinREPathPattern = 'harddisk(?<Disk>\d+)\\partition(?<Partition>\d+)'

$PackageName = 'WinREPartitionSize'
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

function Get-ReagentInfo { param([string]$Text)
    $match = [regex]::Match($Text, $WinREPathPattern)
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{
        Disk      = [int]$match.Groups['Disk'].Value
        Partition = [int]$match.Groups['Partition'].Value
    }
}

function Read-ReagentOutput {
    try {
        $text = (& reagentc.exe /info 2>&1 | Out-String)
    }
    catch { return '' }
    if (-not $text) { return '' }
    return $text
}

function Get-RecoveryPartitions {
    $found = @()
    foreach ($item in @(Get-Partition -ErrorAction Stop)) {
        if (-not $item.GptType) { continue }
        $type = ([string]$item.GptType).Trim('{', '}')
        if ($type -eq $RecoveryGptType) { $found += $item }
    }
    return $found
}

function Get-PartitionSpace { param($Partition)
    $space = [pscustomobject]@{ SizeBytes = $null; FreeBytes = $null; Source = 'None' }
    try {
        $volume = Get-Volume -Partition $Partition -ErrorAction Stop
        if ($volume) {
            $space.SizeBytes = [int64]$volume.Size
            $space.FreeBytes = [int64]$volume.SizeRemaining
            $space.Source = 'Volume'
            return $space
        }
    }
    catch { }
    try {
        $partitionMB = [math]::Round(([double]$Partition.Size) / 1MB)
        foreach ($volume in @(Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop)) {
            if ($null -eq $volume.Capacity) { continue }
            $capacityMB = [math]::Round(([double]$volume.Capacity) / 1MB)
            if ([math]::Abs($capacityMB - $partitionMB) -gt 8) { continue }
            $space.SizeBytes = [int64]$volume.Capacity
            $space.FreeBytes = [int64]$volume.FreeSpace
            $space.Source = 'Win32Volume'
            break
        }
    }
    catch { }
    return $space
}

function Format-Megabytes { param($Bytes)
    if ($null -eq $Bytes) { return 'Unknown' }
    return [string][int][math]::Round(([double]$Bytes) / 1MB)
}

try {
    $ErrorActionPreference = 'Stop'
    $minimumBytes = [int64]$MinimumFreeSpaceMB * 1MB

    $reagentText = Read-ReagentOutput
    $reagent = Get-ReagentInfo -Text $reagentText
    $recoveryPartitions = @(Get-RecoveryPartitions)
    $recoveryCount = @($recoveryPartitions).Count
    $systemLetter = ([string]$env:SystemDrive).TrimEnd(':')

    if ($reagent) {
        Write-IRTLog ('ReagentPath=harddisk{0}\partition{1}' -f $reagent.Disk, $reagent.Partition)
    }
    else {
        Write-IRTLog 'ReagentPath=NotFound'
    }
    Write-IRTLog ('RecoveryPartitions={0}' -f $recoveryCount)

    $target = $null
    $placement = 'None'
    if ($reagent) {
        $target = Get-Partition -DiskNumber $reagent.Disk -PartitionNumber $reagent.Partition -ErrorAction SilentlyContinue
        if ($target) {
            $placement = 'Dedicated'
            if ($target.DriveLetter -eq $systemLetter) { $placement = 'WindowsVolume' }
        }
    }
    if (-not $target -and $recoveryCount -gt 0) {
        $target = @($recoveryPartitions | Sort-Object -Property Size -Descending)[0]
        $placement = 'RecoveryGptType'
    }

    if (-not $target) {
        Exit-Script 0 ('NotApplicable | WinRE=NotConfigured; RecoveryPartitions={0}' -f $recoveryCount)
    }

    $space = Get-PartitionSpace -Partition $target
    $detail = 'Disk={0}; Partition={1}; SizeMB={2}; FreeMB={3}; RequiredFreeMB={4}; RecoveryPartitions={5}; Placement={6}; Source={7}' -f $target.DiskNumber, $target.PartitionNumber, (Format-Megabytes $space.SizeBytes), (Format-Megabytes $space.FreeBytes), $MinimumFreeSpaceMB, $recoveryCount, $placement, $space.Source

    if ($null -eq $space.FreeBytes) {
        Exit-Script 1 "Unknown | $detail"
    }

    $freeMB = [int][math]::Round(([double]$space.FreeBytes) / 1MB)
    if ($freeMB -lt $MinimumFreeSpaceMB) {
        Exit-Script 1 "Small | $detail"
    }

    if ($placement -eq 'WindowsVolume') {
        Exit-Script 0 "Healthy | $detail; WinRE=OnWindowsVolume"
    }

    Exit-Script 0 "Healthy | $detail"
}
catch { Exit-Script 1 ('Error | Reason=DetectionFailed; Type={0}' -f $_.Exception.GetType().Name) }
