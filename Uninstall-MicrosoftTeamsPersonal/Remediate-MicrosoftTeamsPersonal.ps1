# Remediate-MicrosoftTeamsPersonal.ps1
# Intune Remediation REMEDIATION script - "Microsoft Teams Personal" (consumer Teams,
# Microsoft Store MSIX paketi) tum kullanicilar icin kaldirilir ve provisioned kaydi
# silinir (yeni kullanicilara otomatik kurulmamasi icin).
# Kalan paket varsa exit 1, temizse exit 0.
#
# NOT: MicrosoftTeams_8wekyb3d8bbwe paket ailesi, yeni Teams (work/school) makine
# genelinde kurulumu tarafindan da kullanilir. Kurumsal yeni Teams kullaniyorsaniz
# bu scripti dogrulayin.

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'MicrosoftTeams_8wekyb3d8bbwe'

$logPath = 'C:\Temp'
$logFile = Join-Path $logPath 'TeamsPersonal_Remediate.log'
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    "$(Get-Date) $Message" | Out-File $logFile -Append
    Write-Output "$(Get-Date) $Message"
}

Write-Log "Remediation started: Teams Personal ($packageFamily)"

# 1) Calisan Teams sureclerini kapat
Get-Process -Name 'ms-teams', 'msteams', 'Teams' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# 2) Tum kullanicilar icin paketi kaldir
$packages = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
foreach ($pkg in $packages) {
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        Write-Log "Removed: $($pkg.PackageFullName)"
    }
    catch {
        Write-Log "Remove failed for $($pkg.PackageFullName): $($_.Exception.Message)"
    }
}

# 3) Provisioned kaydi sil (yeni kullanicilara otomatik kurulmasin)
Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like 'MicrosoftTeams_*' } |
    ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Provisioned package removed: $($_.PackageName)"
    }

# 4) Dogrulama
$stillPresent = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }
if ($stillPresent) {
    $stillPresent | ForEach-Object { Write-Log "STILL PRESENT: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Remediation completed successfully."
exit 0