<#
.SYNOPSIS
  Remediation script for a plaintext AutoLogon password in Winlogon.

.DESCRIPTION
  Removes only DefaultPassword and verifies absence without reading its contents. Remediation is disabled until logon impact and configuration ownership are reviewed. Exits 0 when absent or removed, 1 when blocked or unsuccessful.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$ConfigurationSourceReviewed = $false
$WinlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$PasswordValueName = 'DefaultPassword'

$PackageName = 'PlaintextAutoLogonPassword'
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
function Test-PasswordValue {
    $key = Get-Item -LiteralPath $WinlogonPath -ErrorAction Stop
    try { return ($key.GetValueNames() -contains $PasswordValueName) }
    finally { $key.Close() }
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { Exit-Script 0 'NotApplicable | Platform=NonWindows' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=Use64BitPowerShell'
    }
    if (-not (Test-Path -LiteralPath $WinlogonPath -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | Winlogon=Absent' }
    if (-not (Test-PasswordValue)) { Exit-Script 0 'Healthy | DefaultPassword=Absent' }
    if (-not $ConfigurationSourceReviewed) {
        Exit-Script 1 'Blocked | DefaultPassword=Present; Reason=ReviewGpoIntuneAndProvisioningSource'
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 'Blocked | DefaultPassword=Present; Reason=RemediationDisabled'
    }
    Remove-ItemProperty -LiteralPath $WinlogonPath -Name $PasswordValueName -ErrorAction Stop
    if (Test-PasswordValue) { Exit-Script 1 'Failed | DefaultPassword=Present; Reason=VerificationFailed' }
    Exit-Script 0 'Fixed | DefaultPassword=Absent; Removed=1'
}
catch { Exit-Script 1 'Error: Registry cleanup failed | Details=Suppressed' }
