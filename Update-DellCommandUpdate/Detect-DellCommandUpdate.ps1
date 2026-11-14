<#
.SYNOPSIS
  Detection script for Dell driver, firmware and optional BIOS updates.

.DESCRIPTION
  Validates Dell Command Update 5.x and scans the selected update types.
  Exits 1 for available updates, pending reboot or errors, otherwise 0.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowBiosUpdates = $false

$PackageName = 'DellCommandUpdate'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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
function Get-DcuPath {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique
    foreach ($root in $roots) {
        $path = Join-Path $root 'Dell\CommandUpdate\dcu-cli.exe'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)O="?Dell (Inc\.?|Technologies Inc\.?)"?(?:,|$)') {
            throw 'DCU signature is not valid or the signer is not Dell'
        }
        $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
        if ($version.FileMajorPart -ne 5) { throw 'Dell Command Update 5.x is required' }
        return $path
    }
    throw 'Dell Command Update CLI is missing; deploy DCU 5.x first'
}
function Invoke-Dcu { param([string]$Path, [string[]]$Arguments)
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
    $code = $process.ExitCode
    $process.Dispose()
    Write-IRTLog "DCU | Arguments=$($Arguments -join ' '); Code=$code"
    return [int]$code
}

try {
    $ErrorActionPreference = 'Stop'
    $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    if ($manufacturer -notmatch '^Dell\b') { Exit-Script 0 'NotApplicable | Manufacturer=NotDell' }
    if (-not [Environment]::Is64BitProcess) { throw '64-bit PowerShell is required' }
    $dcuPath = Get-DcuPath
    $types = 'driver,firmware'
    if ($AllowBiosUpdates) { $types = 'driver,firmware,bios' }
    $scanCode = Invoke-Dcu -Path $dcuPath -Arguments @('/scan', '-silent', "-updateType=$types")
    if ($scanCode -eq 500) { Exit-Script 0 "Healthy | Scope=$types; ScanCode=500; Updates=None" }
    if ($scanCode -eq 0) { Exit-Script 1 "Drift | Scope=$types; ScanCode=0; Updates=Available" }
    if ($scanCode -in @(1, 5)) { Exit-Script 1 "PendingReboot | Scope=$types; ScanCode=$scanCode; Reboot=Manual" }
    Exit-Script 1 "Failed | Scope=$types; ScanCode=$scanCode"
}
catch { Exit-Script 1 "Failed | Error=$($_.Exception.Message)" }
