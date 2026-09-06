# Detect-Spotify.ps1
# Intune Remediation DETECTION script - Microsoft Store'dan kurulan Spotify kurulu mu?
# Paket ailesi: SpotifyAB.SpotifyMusic_zpdnekdrzrea0
# Kuruluysa exit 1 (remediation tetiklenir), degilse exit 0 (saglikli).

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'SpotifyAB.SpotifyMusic_zpdnekdrzrea0'

function Write-Log {
    param([string]$Message)
    Write-Output $Message
}

$found = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }

if ($found) {
    $found | ForEach-Object { Write-Log "DETECTED: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Compliant: Spotify Store paketi kurulu degil."
exit 0
