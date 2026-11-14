<#
.SYNOPSIS
  Detection script for Windows component store corruption.

.DESCRIPTION
  Uses the DISM PowerShell module to scan the running Windows image. Exits 1 for corruption or an unsuccessful scan, 0 for a healthy image or an unsupported operating system. Does not repair the image.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumWindowsBuild = 10240

$PackageName = 'ComponentStore'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = ($Summary -replace '[\r\n]+', ' ').Trim()
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

try {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $operation = 'Prerequisites'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt $MinimumWindowsBuild) {
        Exit-Script 0 'NotApplicable | Reason=UnsupportedOS'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Failed | Reason=RequiresSystem'
    }
    Import-Module Dism -ErrorAction Stop
    $operation = 'ScanHealth'
    Write-IRTLog 'Starting component store scan'
    $image = Repair-WindowsImage -Online -ScanHealth -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue
    $state = [string]$image.ImageHealthState
    switch ($state) {
        'Healthy' { Exit-Script 0 'Healthy | ImageHealthState=Healthy; Scan=Full' }
        'Repairable' { Exit-Script 1 'Drift | ImageHealthState=Repairable; Action=RestoreHealth' }
        'NonRepairable' { Exit-Script 1 'Failed | ImageHealthState=NonRepairable; Action=ManualRecovery' }
        default { Exit-Script 1 'Failed | Reason=UnknownImageHealthState; Action=ReviewDISMLog' }
    }
}
catch {
    Exit-Script 1 ('Error: Operation={0}; HResult=0x{1:X8}; Action=ReviewDISMLog' -f $operation, $_.Exception.HResult)
}
