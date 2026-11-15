<#
.SYNOPSIS
  Detection script for a plaintext AutoLogon password in Winlogon.

.DESCRIPTION
  Checks value names without reading the password. Exits 1 when DefaultPassword exists, including an empty value, or on an error. Exits 0 when absent or not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WinlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$PasswordValueName = 'DefaultPassword'

$PackageName = 'PlaintextAutoLogonPassword'
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

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { Exit-Script 0 'NotApplicable | Platform=NonWindows' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=Use64BitPowerShell'
    }
    if (-not (Test-Path -LiteralPath $WinlogonPath -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | Winlogon=Absent' }
    $key = Get-Item -LiteralPath $WinlogonPath -ErrorAction Stop
    try { $present = $key.GetValueNames() -contains $PasswordValueName }
    finally { $key.Close() }
    if ($present) { Exit-Script 1 'Drift | DefaultPassword=Present; PasswordRead=False' }
    Exit-Script 0 'Healthy | DefaultPassword=Absent'
}
catch { Exit-Script 1 'Error: Registry inspection failed | Details=Suppressed' }
