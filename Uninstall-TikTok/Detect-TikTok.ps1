# Detect-TikTok.ps1
# Intune Remediation DETECTION script - Microsoft Store'dan kurulan TikTok kurulu mu?
# Paket ailesi: BytedancePte.Ltd.TikTok_6yccndn6064se
# Kuruluysa exit 1 (remediation tetiklenir), degilse exit 0 (saglikli).

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'BytedancePte.Ltd.TikTok_6yccndn6064se'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

$found = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }

if ($found) {
    $found | ForEach-Object { Write-Log "DETECTED: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Compliant: TikTok Store paketi kurulu degil."
exit 0
