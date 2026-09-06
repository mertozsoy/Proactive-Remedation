# =====================================================================
# EFI Partition Detection Script
# Version : 1.1
# Purpose : Detect low free space in EFI System Partition
# Intune Detection Script
# =====================================================================

$LogFolder = "C:\Temp"
$LogFile = Join-Path $LogFolder "EFIPartitionDetection.log"

$MinFreeMB = 60

if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

if (Test-Path $LogFile) {
    Remove-Item $LogFile -Force
}

$Report = [System.Text.StringBuilder]::new()

function Write-Log {
    param(
        [string]$Message,
        [string]$Level="INFO"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[$Time] [$Level] $Message"

    [void]$Report.AppendLine($Line)
}

function Write-ReportOutput {
    $Raw = $Report.ToString()

    $Raw -split [Environment]::NewLine | Where-Object { $_.Trim() } | Out-File -FilePath $LogFile -Encoding utf8

    $Cleaned = $Raw -split [Environment]::NewLine |
               Where-Object { $_.Trim() -and $_ -notmatch '^\[.*\] \[INFO\] =+$' } |
               ForEach-Object { $_ -replace '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[\w+\] ', '' }

    $Cleaned -join ' ___ ' | Write-Output
}

$Result = 1

try {

    mountvol S: /S | Out-Null
    Start-Sleep -Seconds 2

    $Volume = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='S:'"

    if (!$Volume) {
        Write-Log "ERROR : EFI partition could not be mounted." "ERROR"
        Write-ReportOutput
        exit 1
    }

    $TotalMB = [math]::Round($Volume.Size / 1MB, 2)
    $FreeMB  = [math]::Round($Volume.FreeSpace / 1MB, 2)

    Write-Log ""
    Write-Log "Folder Sizes"
    Write-Log "--------------------------------------------"

    Get-ChildItem S:\ -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {

        $Size = (
            Get-ChildItem $_.FullName -Force -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum
        ).Sum

        if ($null -eq $Size) { $Size = 0 }

        $SizeMB = [math]::Round($Size / 1MB, 2)

        Write-Log ("{0,-30} {1,8} MB" -f $_.Name, $SizeMB)

        if ($_.Name -eq "EFI") {
            Get-ChildItem "S:\EFI" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {

                $SubSize = (
                    Get-ChildItem $_.FullName -Force -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum
                ).Sum

                if ($null -eq $SubSize) { $SubSize = 0 }

                $SubSizeMB = [math]::Round($SubSize / 1MB, 2)

                Write-Log ("  {0,-28} {1,8} MB" -f $_.Name, $SubSizeMB)

                if ($_.Name -eq "HP") {
                    Get-ChildItem "S:\EFI\HP" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {

                        $Sub2Size = (
                            Get-ChildItem $_.FullName -Force -Recurse -File -ErrorAction SilentlyContinue |
                            Measure-Object Length -Sum
                        ).Sum

                        if ($null -eq $Sub2Size) { $Sub2Size = 0 }

                        $Sub2SizeMB = [math]::Round($Sub2Size / 1MB, 2)

                        Write-Log ("    {0,-26} {1,8} MB" -f $_.Name, $Sub2SizeMB)
                    }
                }
            }
        }
    }

    Write-Log ""

    if ($FreeMB -lt $MinFreeMB) {
        Write-Log "STATUS : LOW FREE SPACE DETECTED"
        $Result = 1
    }
    else {
        Write-Log "STATUS : HEALTHY"
        $Result = 0
    }
}
catch {
    Write-Log ""
    Write-Log "ERROR : $($_.Exception.Message)" "ERROR"
    $Result = 1
}
finally {

    mountvol S: /D | Out-Null

    Write-Log ""
    Write-Log "EFI partition unmounted."

    Write-Log ""
    Write-Log "================ SUMMARY ================"
    Write-Log "Computer    : $env:COMPUTERNAME"
    Write-Log "EFI Size    : $TotalMB MB"
    Write-Log "Free Space  : $FreeMB MB"
    Write-Log "Threshold   : $MinFreeMB MB"
    Write-Log "Result      : $(if($Result -eq 0){'Healthy'}else{'Low Free Space'})"
    Write-Log "========================================="

    Write-ReportOutput
}

exit $Result
