# Remediate-Spotify.ps1
# Intune Remediation REMEDIATION script - Microsoft Store'dan kurulan Spotify
# tum kullanicilar icin kaldirilir ve provisioned kaydi silinir.
# Kalan paket varsa exit 1, temizse exit 0.

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'SpotifyAB.SpotifyMusic_zpdnekdrzrea0'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

Write-Log "Remediation started: Spotify ($packageFamily)"

# 1) Calisan Spotify sureclerini kapat
Get-Process -Name 'Spotify', 'SpotifyMigrator' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# 2) Tum kullanicilar icin Store paketini kaldir
$packages = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if (-not $packages) {
    Write-Log "Spotify Store paketi bulunamadi; kaldirilacak paket yok."
}

foreach ($pkg in $packages) {
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        Write-Log "Spotify Store paketi kaldirildi: $($pkg.PackageFullName)"
    }
    catch {
        Write-Log "Spotify Store paketi kaldirilamadi: $($pkg.PackageFullName) - $($_.Exception.Message)"
    }
}

# 3) Provisioned kaydi sil (yeni kullanicilara otomatik kurulmasin)
Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like 'SpotifyAB.SpotifyMusic_*' } |
    ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Spotify provisioned paketi kaldirildi: $($_.PackageName)"
    }

# 4) Dogrulama
$stillPresent = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if ($stillPresent) {
    $stillPresent | ForEach-Object { Write-Log "STILL PRESENT: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Remediation tamamlandi: Spotify Store paketi cihazda bulunmuyor."
exit 0
