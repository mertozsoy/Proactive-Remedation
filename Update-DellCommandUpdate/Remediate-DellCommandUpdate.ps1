<#
.SYNOPSIS
  Remediation script for Dell driver, firmware and optional BIOS updates.

.DESCRIPTION
  Validates Dell Command Update 5.x, applies driver and firmware updates first,
  then optionally BIOS updates with automatic BitLocker suspension. Never reboots.
  Exits 0 only when follow-up scans find no updates and no reboot is pending.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowBiosUpdates = $false

$PackageName = 'DellCommandUpdate'
$Phase = 'Remediate'
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
    $scopes = @('driver,firmware')
    if ($AllowBiosUpdates) { $scopes += 'bios' }
    $applied = $false
    foreach ($scope in $scopes) {
        $scanCode = Invoke-Dcu -Path $dcuPath -Arguments @('/scan', '-silent', "-updateType=$scope")
        if ($scanCode -eq 500) { continue }
        if ($scanCode -in @(1, 5)) { Exit-Script 1 "PendingReboot | Scope=$scope; ScanCode=$scanCode; Reboot=Manual" }
        if ($scanCode -ne 0) { Exit-Script 1 "Failed | Scope=$scope; ScanCode=$scanCode" }
        $arguments = @('/applyUpdates', '-silent', "-updateType=$scope", '-reboot=disable')
        if ($scope -eq 'bios') { $arguments += '-autoSuspendBitLocker=enable' }
        $applyCode = Invoke-Dcu -Path $dcuPath -Arguments $arguments
        $verifyCode = Invoke-Dcu -Path $dcuPath -Arguments @('/scan', '-silent', "-updateType=$scope")
        if ($applyCode -in @(1, 5) -or $verifyCode -in @(1, 5)) {
            Exit-Script 1 "PendingReboot | Scope=$scope; ApplyCode=$applyCode; VerifyCode=$verifyCode; Reboot=Manual"
        }
        if ($applyCode -ne 0) { Exit-Script 1 "Failed | Scope=$scope; ApplyCode=$applyCode; VerifyCode=$verifyCode" }
        if ($verifyCode -ne 500) { Exit-Script 1 "Failed | Scope=$scope; ApplyCode=$applyCode; VerifyCode=$verifyCode; Updates=Unresolved" }
        $applied = $true
    }
    $types = $scopes -join ','
    $finalCode = Invoke-Dcu -Path $dcuPath -Arguments @('/scan', '-silent', "-updateType=$types")
    if ($finalCode -in @(1, 5)) { Exit-Script 1 "PendingReboot | Scope=$types; ScanCode=$finalCode; Reboot=Manual" }
    if ($finalCode -ne 500) { Exit-Script 1 "Failed | Scope=$types; VerifyCode=$finalCode; Updates=Unresolved" }
    if ($applied) { Exit-Script 0 "Fixed | Scope=$types; VerifyCode=500; Reboot=NotRequested" }
    Exit-Script 0 "Healthy | Scope=$types; ScanCode=500; Updates=None"
}
catch { Exit-Script 1 "Failed | Error=$($_.Exception.Message)" }
