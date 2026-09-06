# Detect-Netflix.ps1
# Intune Remediation DETECTION script - Microsoft Store'dan kurulan Netflix kurulu mu?
# Paket ailesi: 4DF9E0F8.Netflix_mcm4njqhnhss8
# Kuruluysa exit 1 (remediation tetiklenir), degilse exit 0 (saglikli).

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = '4DF9E0F8.Netflix_mcm4njqhnhss8'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

$found = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }

if ($found) {
    $found | ForEach-Object { Write-Log "DETECTED: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Compliant: Netflix Store paketi kurulu degil."
exit 0
