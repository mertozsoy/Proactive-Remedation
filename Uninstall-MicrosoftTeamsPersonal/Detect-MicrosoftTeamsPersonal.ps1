# Detect-MicrosoftTeamsPersonal.ps1
# Intune Remediation DETECTION script - "Microsoft Teams Personal" (consumer Teams,
# Microsoft Store MSIX paketi) kurulu mu?
# Paket ailesi: MicrosoftTeams_8wekyb3d8bbwe
# Kuruluysa exit 1 (remediation tetiklenir), degilse exit 0 (saglikli).

$ErrorActionPreference = 'SilentlyContinue'
$packageFamily = 'MicrosoftTeams_8wekyb3d8bbwe'

$logPath = 'C:\Temp'
$logFile = Join-Path $logPath 'TeamsPersonal_Detect.log'
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    "$(Get-Date) $Message" | Out-File $logFile -Append
    Write-Output "$(Get-Date) $Message"
}

$found = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFamilyName -eq $packageFamily }

if ($found) {
    $found | ForEach-Object { Write-Log "DETECTED: $($_.PackageFullName)" }
    exit 1
}

Write-Log "Not detected: Teams Personal kurulu degil."
exit 0