# Detect-TouchVPN.ps1
# Intune Remediation DETECTION script - Microsoft Store'dan kurulan TouchVPN kurulu mu?
# Paket ailesi: 6F71D7A7.TouchVPN_nsbqstbb9qxb6
# Kuruluysa exit 1 (remediation tetiklenir), degilse exit 0 (saglikli).

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = '6F71D7A7.TouchVPN_nsbqstbb9qxb6'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

$found = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }

if ($found) {
    $found | ForEach-Object { Write-Log "DETECTED: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Compliant: TouchVPN Store paketi kurulu degil."
exit 0
