$logDir = "C:\Temp"
$logFile = "$logDir\#windows updates - diagnostics.log"
$setupDiagUrl = "https://go.microsoft.com/fwlink/?linkid=870142"
$setupDiagPath = "$logDir\SetupDiag.exe"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

# --- Eski log dosyasini sil ---
if (Test-Path -LiteralPath $logFile) {
    Remove-Item -LiteralPath $logFile -Force
    Write-Host "Eski log dosyasi silindi: $logFile"
}

# --- SetupDiag indir (her calistirmada guncel) ---
try {
    $webClient = New-Object System.Net.WebClient
    Write-Host "SetupDiag indiriliyor..."
    $webClient.DownloadFile($setupDiagUrl, $setupDiagPath)
    Write-Host "SetupDiag indirme tamamlandi: $setupDiagPath"
}
catch {
    Write-Host "SetupDiag indirilemedi: $($_.Exception.Message)"
    exit 0
}

$checkLogs = Test-Path -Path "$logDir\logs*.zip"
if ($checkLogs) {
    Remove-Item -Path "$logDir\logs*.zip" -Force -Recurse
    Write-Host "Eski log zip'leri temizlendi"
}

Write-Host "SetupDiag calistiriliyor..."
Start-Process -FilePath $setupDiagPath -ArgumentList "/Output:`"$logFile`"" -Wait -NoNewWindow
Write-Host "SetupDiag calistirildi, log dosyasi bekleniyor..."

# --- Log dosyasi olusana kadar bekle (en fazla 15 dakika) ---
$timeoutMin = 15
$elapsedSec = 0
$logReady = $false
while ($elapsedSec -lt ($timeoutMin * 60)) {
    Start-Sleep -Seconds 10
    $elapsedSec += 10
    if (Test-Path -LiteralPath $logFile) {
        $fileInfo = Get-Item -LiteralPath $logFile -ErrorAction SilentlyContinue
        if ($fileInfo -and $fileInfo.Length -gt 0) {
            $logReady = $true
            break
        }
    }
    Write-Host "  Bekleniyor... $elapsedSec sn"
}

if (-not $logReady) {
    Write-Host "Zaman asimi: log dosyasi olusturulamadi ($logFile)"
    exit 0
}

# --- Ilk 2 satiri Intune output loguna yaz ---
Write-Host "=== Windows Updates Diagnostics (ilk 2 satir) ==="
$lines = Get-Content -LiteralPath $logFile -TotalCount 2 -ErrorAction SilentlyContinue
if ($lines) {
    $lines | ForEach-Object { Write-Host $_ }
}
else {
    Write-Host "Log dosyasi bos: $logFile"
}

exit 0
