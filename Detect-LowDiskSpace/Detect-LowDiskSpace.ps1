.<#
.SYNOPSIS
  Detection script for low disk space on C: drive.

.DESCRIPTION
  Reports C: drive total, used, free space and user profile folder sizes.
  Exits 0 if free space >= 30 GB, exits 1 if below.

.NOTES
  Author: Mert Ozsoy
  Version: 1.7
  Run As: System
#>

$OutputEncoding = [System.Text.Encoding]::UTF8
$LogFolder = "C:\Temp"
$LogFile = Join-Path $LogFolder "Detect-LowDiskSpace.log"
$MinGBFree = 30

if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

if (Test-Path $LogFile) {
    Remove-Item $LogFile -Force
}

$Report = [System.Text.StringBuilder]::new()

function Write-Log {
    param([string]$Message)
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Time] $Message"
    [void]$Report.AppendLine($Line)
}

function Write-ReportOutput {
    $Raw = $Report.ToString()
    $Raw -split [Environment]::NewLine | Where-Object { $_.Trim() } | Out-File -FilePath $LogFile -Encoding utf8

    $Cleaned = $Raw -split [Environment]::NewLine |
               Where-Object { $_.Trim() } |
               ForEach-Object { $_ -replace '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ', '' }

    $Cleaned -join ' ___ ' | Write-Output
}

Write-Log "================"
Write-Log "C: DISK RAPORU"
Write-Log "================"

# --- C: disk info ---
try {
    $cimDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    $freeBytes = [int64]$cimDisk.FreeSpace
    $totalBytes = [int64]$cimDisk.Size
    $usedBytes = $totalBytes - $freeBytes

    $totalGB  = [math]::Round($totalBytes / 1GB, 2)
    $usedGB   = [math]::Round($usedBytes  / 1GB, 2)
    $freeGB   = [math]::Round($freeBytes  / 1GB, 2)
    $freePct  = [math]::Round(($freeBytes / $totalBytes) * 100, 1)
    $usedPct  = [math]::Round(($usedBytes / $totalBytes) * 100, 1)
} catch {
    Write-Log "HATA: C: diski bilgisi okunamadi"
    Write-ReportOutput
    exit 1
}

Write-Log "Toplam Boyut : $totalGB GB"
Write-Log "Kullanilan   : $usedGB GB (%$usedPct)"
Write-Log "Bos Alan     : $freeGB GB (%$freePct)"

# --- Profile folders ---
Write-Log " "
Write-Log "================"
Write-Log "KULLANICI PROFILLERI"
Write-Log "================"

$usersPath = "C:\Users"
if (Test-Path -LiteralPath $usersPath) {
    $excludeDirs = @('All Users', 'Default', 'Default User', 'Public')
    $profileDirs = Get-ChildItem -LiteralPath $usersPath -Directory -Force -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -notin $excludeDirs }
    if ($profileDirs) {
        Write-Log "Toplam: $($profileDirs.Count) profil"

        function Get-FolderSize {
            param([string]$FolderPath)
            $size = [int64]0
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($FolderPath)) {
                    try { $size += [System.IO.FileInfo]::new($f).Length } catch {}
                }
                foreach ($d in [System.IO.Directory]::EnumerateDirectories($FolderPath)) {
                    try { $size += (Get-FolderSize -FolderPath $d).Size } catch {}
                }
            } catch {}
            return [PSCustomObject]@{ Size = $size }
        }

        foreach ($pDir in $profileDirs) {
            try {
                $result = Get-FolderSize -FolderPath $pDir.FullName
                $sizeGB = [math]::Round($result.Size / 1GB, 2)
                Write-Log "$($pDir.Name) : $sizeGB GB"
            } catch {
                Write-Log "$($pDir.Name) : HESAPLANAMADI"
            }
        }
    } else {
        Write-Log "Klasor bulunamadi"
    }
} else {
    Write-Log "C:\Users yok"
}

Write-Log " "
Write-Log "================"
Write-Log "SONUC"
Write-Log "================"

if ($freeBytes -ge ($MinGBFree * 1GB)) {
    Write-Log "Bos alan $MinGBFree GB ve uzeri. Sorun yok."
} else {
    Write-Log "Bos alan $MinGBFree GB altinda."
    Write-Log "Mevcut bos alan: $freeGB GB"
}

Write-ReportOutput

if ($freeBytes -ge ($MinGBFree * 1GB)) {
    exit 0
}
exit 1
