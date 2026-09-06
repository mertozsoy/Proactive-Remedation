# Remediate-Disney.ps1
# Intune Remediation REMEDIATION script - Microsoft Store'dan kurulan Disney
# tum kullanicilar icin kaldirilir ve provisioned kaydi silinir.
# Kalan paket varsa exit 1, temizse exit 0.

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'Disney.37853FC22B2CE_6rarf9sa4v8jt'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

Write-Log "Remediation started: Disney ($packageFamily)"

# 1) Calisan Disney sureclerini kapat
Get-Process -Name 'Disney' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# 2) Tum kullanicilar icin Store paketini kaldir
$packages = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if (-not $packages) {
    Write-Log "Disney Store paketi bulunamadi; kaldirilacak paket yok."
}

foreach ($pkg in $packages) {
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        Write-Log "Disney Store paketi kaldirildi: $($pkg.PackageFullName)"
    }
    catch {
        Write-Log "Disney Store paketi kaldirilamadi: $($pkg.PackageFullName) - $($_.Exception.Message)"
    }
}

# 3) Provisioned kaydi sil (yeni kullanicilara otomatik kurulmasin)
Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like 'Disney.37853FC22B2CE_*' } |
    ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Disney provisioned paketi kaldirildi: $($_.PackageName)"
    }

# 4) Dogrulama
$stillPresent = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if ($stillPresent) {
    $stillPresent | ForEach-Object { Write-Log "STILL PRESENT: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Remediation tamamlandi: Disney Store paketi cihazda bulunmuyor."
exit 0
