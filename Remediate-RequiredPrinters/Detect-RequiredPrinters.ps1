<#
.SYNOPSIS
  Detection script for required user printer connections.

.DESCRIPTION
  Compares installed printer names with an approved UNC list in the current user context. Exits 1 if a required connection is missing or enumeration fails, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RequiredPrinters = @()

$PackageName = 'RequiredPrinters'
$Phase = 'Detect'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"

function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 1 'Failed | Reason=UserContextRequired'
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $LogFile) -Force -ErrorAction Stop | Out-Null
    if ($RequiredPrinters.Count -eq 0) { Exit-Script 0 'NotApplicable | RequiredPrinters=None' }
    foreach ($connection in $RequiredPrinters) {
        if ($connection -isnot [string] -or $connection -notmatch '^\\\\[^\\/\s]+\\[^\\/]+$' -or
            $connection -match '[\x00-\x1f*?]' -or $connection -ne $connection.Trim()) {
            Exit-Script 1 'Failed | Reason=InvalidPrinterConfiguration'
        }
    }
    $required = @($RequiredPrinters | Sort-Object -Unique)
    Import-Module PrintManagement -ErrorAction Stop
    $installedNames = @(Get-Printer -ErrorAction Stop | Select-Object -ExpandProperty Name)
    $missing = @($required | Where-Object { $installedNames -notcontains $_ })
    if ($missing.Count -gt 0) {
        Exit-Script 1 "Drift | Required=$($required.Count); Missing=$($missing.Count)"
    }
    Exit-Script 0 "Healthy | Required=$($required.Count); Missing=0"
}
catch { Exit-Script 1 "Error: PrinterDetection | HResult=$($_.Exception.HResult)" }
