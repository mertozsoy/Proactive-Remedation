<#
.SYNOPSIS
  Detection script for unapproved direct Entra user administrators.

.DESCRIPTION
  Checks direct User members of the built-in Administrators group with S-1-12-1- SIDs, excluding AllowedSids. Does not identify the enrolling or primary user. Exits 1 on drift or error and 0 when healthy or not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowedSids = @()

$PackageName = 'EnrollingUserAdmin'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=Requires64BitPowerShell'
    }
    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.LocalAccounts)) {
        Exit-Script 0 'NotApplicable | Reason=LocalAccountsUnavailable'
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $approved = @($AllowedSids | ForEach-Object {
        $sid = [System.Security.Principal.SecurityIdentifier]::new([string]$_)
        $sid.Value
    })
    $adminSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $members = @(Get-LocalGroupMember -SID $adminSid -ErrorAction Stop)
    $targets = @($members | Where-Object {
        $_.ObjectClass -eq 'User' -and
        $_.SID.Value -like 'S-1-12-1-*' -and
        $approved -notcontains $_.SID.Value
    })
    if ($targets.Count -eq 0) { Exit-Script 0 'Healthy | Candidates=0' }
    Exit-Script 1 "Drift | Candidates=$($targets.Count); Scope=DirectEntraUsers"
}
catch { Exit-Script 1 "Error: Failed | Reason=InspectionFailed; Type=$($_.Exception.GetType().Name)" }
