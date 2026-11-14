<#
.SYNOPSIS
  Remediation script for a repairable Windows component store.

.DESCRIPTION
  Rechecks component store health, repairs a repairable image with DISM RestoreHealth and verifies with a full scan. Uses the configured Windows repair source unless an optional source is supplied. Never restarts Windows. Exits 0 only for a healthy image with no restart requested by this repair, 1 for incomplete repair or errors.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$RepairSources = @()
$LimitAccess = $false
$MinimumWindowsBuild = 10240

$PackageName = 'ComponentStore'
$Phase = 'Remediate'
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
    $operation = 'CheckHealth'
    $image = Repair-WindowsImage -Online -CheckHealth -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue
    $state = [string]$image.ImageHealthState
    if ($state -eq 'Healthy') { Exit-Script 0 'Healthy | ImageHealthState=Healthy; Action=None' }
    if ($state -eq 'NonRepairable') {
        Exit-Script 1 'Failed | ImageHealthState=NonRepairable; Action=ManualRecovery'
    }
    if ($state -ne 'Repairable') {
        Exit-Script 1 'Failed | Reason=UnknownImageHealthState; Action=ReviewDISMLog'
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 'Drift | ImageHealthState=Repairable; Remediation=Disabled'
    }
    $sources = @($RepairSources | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($LimitAccess -and $sources.Count -eq 0) {
        Exit-Script 1 'Failed | Reason=LimitAccessRequiresExplicitSource'
    }
    $repairParameters = @{
        Online = $true
        RestoreHealth = $true
        NoRestart = $true
        ErrorAction = 'Stop'
        WarningAction = 'SilentlyContinue'
    }
    if ($sources.Count -gt 0) { $repairParameters.Source = $sources }
    if ($LimitAccess) { $repairParameters.LimitAccess = $true }
    $operation = 'RestoreHealth'
    Write-IRTLog "Starting RestoreHealth; ExplicitSources=$($sources.Count); LimitAccess=$LimitAccess"
    $repair = Repair-WindowsImage @repairParameters
    if ($repair.RestartNeeded) {
        Exit-Script 1 'PendingRestart | Action=ArrangeMaintenanceRestart; AutomaticRestart=False'
    }
    $operation = 'VerifyScanHealth'
    $verified = Repair-WindowsImage -Online -ScanHealth -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue
    $verifiedState = [string]$verified.ImageHealthState
    if ($verifiedState -eq 'Healthy' -and -not $verified.RestartNeeded) {
        Exit-Script 0 'Fixed | ImageHealthState=Healthy; Verification=FullScan; RestartNeeded=False'
    }
    if ($verified.RestartNeeded) {
        Exit-Script 1 'PendingRestart | Action=ArrangeMaintenanceRestart; AutomaticRestart=False'
    }
    if ($verifiedState -notin @('Healthy', 'Repairable', 'NonRepairable')) {
        Exit-Script 1 'Failed | Reason=UnknownImageHealthState; Action=ReviewDISMLog'
    }
    Exit-Script 1 "Failed | ImageHealthState=$verifiedState; Action=ReviewDISMLog"
}
catch {
    Exit-Script 1 ('Error: Operation={0}; HResult=0x{1:X8}; Action=ReviewDISMLog' -f $operation, $_.Exception.HResult)
}
