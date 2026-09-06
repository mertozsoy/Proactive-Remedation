# Detect-InstagramBeta.ps1
# Intune Remediation DETECTION script - Microsoft Store'dan kurulan Instagram Beta kurulu mu?
# Paket ailesi: Facebook.InstagramBeta_8xx8rvfyw5nnt
# Kuruluysa exit 1 (remediation tetiklenir), degilse exit 0 (saglikli).

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'Facebook.InstagramBeta_8xx8rvfyw5nnt'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

$found = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }

if ($found) {
    $found | ForEach-Object { Write-Log "DETECTED: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Compliant: Instagram Beta Store paketi kurulu degil."
exit 0
