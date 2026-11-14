<#
.SYNOPSIS
  Remediation script for required user printer connections.

.DESCRIPTION
  Adds only missing approved UNC printer connections as the current user and reads back the installed list. Exits 0 only when all required connections exist. Does not change driver security policy or remove printers.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RequiredPrinters = @()

$PackageName = 'RequiredPrinters'
$Phase = 'Remediate'
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
    if ($missing.Count -eq 0) { Exit-Script 0 "Healthy | Required=$($required.Count); Missing=0" }
    $addErrors = 0
    $index = 0
    foreach ($connection in $missing) {
        $index++
        try {
            Add-Printer -ConnectionName $connection -ErrorAction Stop | Out-Null
            Write-IRTLog "ConnectionIndex=$index; Result=AddCompleted"
        }
        catch {
            $addErrors++
            Write-IRTLog "ConnectionIndex=$index; Result=AddFailed; HResult=$($_.Exception.HResult)" 'WARN'
        }
    }
    $installedNames = @(Get-Printer -ErrorAction Stop | Select-Object -ExpandProperty Name)
    $remaining = @($required | Where-Object { $installedNames -notcontains $_ })
    $added = @($missing | Where-Object { $installedNames -contains $_ }).Count
    if ($remaining.Count -gt 0) {
        Exit-Script 1 "Failed | Required=$($required.Count); Added=$added; Missing=$($remaining.Count); AddErrors=$addErrors"
    }
    Exit-Script 0 "Fixed | Required=$($required.Count); Added=$added; Missing=0; AddErrors=$addErrors"
}
catch { Exit-Script 1 "Error: PrinterRemediation | HResult=$($_.Exception.HResult)" }
