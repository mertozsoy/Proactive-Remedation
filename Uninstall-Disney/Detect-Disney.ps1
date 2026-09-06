# Detect-Disney.ps1
# Intune Remediation DETECTION script - Microsoft Store'dan kurulan Disney kurulu mu?
# Paket ailesi: Disney.37853FC22B2CE_6rarf9sa4v8jt
# Kuruluysa exit 1 (remediation tetiklenir), degilse exit 0 (saglikli).

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'Disney.37853FC22B2CE_6rarf9sa4v8jt'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

$found = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }

if ($found) {
    $found | ForEach-Object { Write-Log "DETECTED: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Compliant: Disney Store paketi kurulu degil."
exit 0
