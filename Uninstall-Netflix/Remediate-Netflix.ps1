# Remediate-Netflix.ps1
# Intune Remediation REMEDIATION script - Microsoft Store'dan kurulan Netflix
# tum kullanicilar icin kaldirilir ve provisioned kaydi silinir.
# Kalan paket varsa exit 1, temizse exit 0.

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = '4DF9E0F8.Netflix_mcm4njqhnhss8'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

Write-Log "Remediation started: Netflix ($packageFamily)"

# 1) Calisan Netflix sureclerini kapat
Get-Process -Name 'Netflix' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# 2) Tum kullanicilar icin Store paketini kaldir
$packages = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if (-not $packages) {
    Write-Log "Netflix Store paketi bulunamadi; kaldirilacak paket yok."
}

foreach ($pkg in $packages) {
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        Write-Log "Netflix Store paketi kaldirildi: $($pkg.PackageFullName)"
    }
    catch {
        Write-Log "Netflix Store paketi kaldirilamadi: $($pkg.PackageFullName) - $($_.Exception.Message)"
    }
}

# 3) Provisioned kaydi sil (yeni kullanicilara otomatik kurulmasin)
Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like '4DF9E0F8.Netflix_*' } |
    ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Netflix provisioned paketi kaldirildi: $($_.PackageName)"
    }

# 4) Dogrulama
$stillPresent = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if ($stillPresent) {
    $stillPresent | ForEach-Object { Write-Log "STILL PRESENT: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Remediation tamamlandi: Netflix Store paketi cihazda bulunmuyor."
exit 0
