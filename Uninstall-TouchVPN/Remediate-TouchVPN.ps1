# Remediate-TouchVPN.ps1
# Intune Remediation REMEDIATION script - Microsoft Store'dan kurulan TouchVPN
# tum kullanicilar icin kaldirilir ve provisioned kaydi silinir.
# Kalan paket varsa exit 1, temizse exit 0.

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = '6F71D7A7.TouchVPN_nsbqstbb9qxb6'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

Write-Log "Remediation started: TouchVPN ($packageFamily)"

# 1) Calisan TouchVPN sureclerini kapat
Get-Process -Name 'TouchVPN' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# 2) Tum kullanicilar icin Store paketini kaldir
$packages = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if (-not $packages) {
    Write-Log "TouchVPN Store paketi bulunamadi; kaldirilacak paket yok."
}

foreach ($pkg in $packages) {
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        Write-Log "TouchVPN Store paketi kaldirildi: $($pkg.PackageFullName)"
    }
    catch {
        Write-Log "TouchVPN Store paketi kaldirilamadi: $($pkg.PackageFullName) - $($_.Exception.Message)"
    }
}

# 3) Provisioned kaydi sil (yeni kullanicilara otomatik kurulmasin)
Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like '6F71D7A7.TouchVPN_*' } |
    ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        Write-Log "TouchVPN provisioned paketi kaldirildi: $($_.PackageName)"
    }

# 4) Dogrulama
$stillPresent = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if ($stillPresent) {
    $stillPresent | ForEach-Object { Write-Log "STILL PRESENT: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Remediation tamamlandi: TouchVPN Store paketi cihazda bulunmuyor."
exit 0
