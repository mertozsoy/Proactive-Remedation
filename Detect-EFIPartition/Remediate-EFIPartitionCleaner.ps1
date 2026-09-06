# =====================================================================
# EFI Partition Detection & Cleaner Script
# Description : Detects EFI folder sizes, deletes DEVFW contents,
#               logs before/after sizes
# =====================================================================

$LogFolder = "C:\Temp"
$LogFile = Join-Path $LogFolder "EFIPartitionCleaner.log"

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

function Get-FolderSize {
    param([string]$Path)
    $Size = (Get-ChildItem $Path -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $Size) { $Size = 0 }
    return $Size
}

function Write-FolderTree {
    Write-Log "Folder Sizes"
    Write-Log "--------------------------------------------"

    Get-ChildItem S:\ -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $SizeMB = [math]::Round((Get-FolderSize -Path $_.FullName) / 1MB, 2)
        Write-Log ("{0,-30} {1,8} MB" -f $_.Name, $SizeMB)

        if ($_.Name -eq "EFI") {
            Get-ChildItem "S:\EFI" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $SubSizeMB = [math]::Round((Get-FolderSize -Path $_.FullName) / 1MB, 2)
                Write-Log ("  {0,-28} {1,8} MB" -f $_.Name, $SubSizeMB)

                if ($_.Name -eq "HP") {
                    Get-ChildItem "S:\EFI\HP" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        $Sub2SizeMB = [math]::Round((Get-FolderSize -Path $_.FullName) / 1MB, 2)
                        Write-Log ("    {0,-26} {1,8} MB" -f $_.Name, $Sub2SizeMB)
                    }
                }
            }
        }
    }
}

$Result = 1

try {

    Write-Log "=========================================================="
    Write-Log "EFI Detection & Cleaner Started"
    Write-Log "Computer : $env:COMPUTERNAME"
    Write-Log ""

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

    Write-Log "========== BEFORE CLEANUP =========="
    Write-FolderTree

    $DevfwPath = "S:\EFI\HP\DEVFW"
    if (Test-Path $DevfwPath) {
        Write-Log ""
        Write-Log "========== CLEANING DEVFW =========="

        $DevfwFiles = Get-ChildItem "$DevfwPath\*" -Force -File -ErrorAction SilentlyContinue
        $DevfwSize = 0
        foreach ($file in $DevfwFiles) {
            $DevfwSize += $file.Length
            Write-Log ("  Deleting : {0,-30} {1,8} MB" -f $file.Name, [math]::Round($file.Length / 1MB, 2))
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }

        $DevfwSizeMB = [math]::Round($DevfwSize / 1MB, 2)
        Write-Log ""
        Write-Log ("Deleted {0} files, freed {1} MB" -f $DevfwFiles.Count, $DevfwSizeMB)
    }
    else {
        Write-Log "DEVFW folder not found, skipping cleanup."
    }

    Write-Log ""
    Write-Log "========== AFTER CLEANUP =========="
    Write-FolderTree

    $FreeAfter = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='S:'").FreeSpace / 1MB, 2)
    $FreedMB = [math]::Round($FreeAfter - $FreeMB, 2)

    Write-Log ""
    Write-Log "STATUS : LOW FREE SPACE DETECTED"
    Write-Log "Freed Space : $FreedMB MB"
    $Result = 1
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
    Write-Log "Free Space Before : $FreeMB MB"
    Write-Log "Free Space After  : $FreeAfter MB"
    Write-Log "Threshold   : $MinFreeMB MB"
    Write-Log "Result      : Devfw Cleaned"
    Write-Log "========================================="

    Write-ReportOutput
}

exit $Result
