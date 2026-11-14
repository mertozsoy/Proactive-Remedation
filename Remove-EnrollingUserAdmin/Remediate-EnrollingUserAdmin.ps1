<#
.SYNOPSIS
  Remediation script for unapproved direct Entra user administrators.

.DESCRIPTION
  Removes only direct User members with S-1-12-1- SIDs outside AllowedSids. Disabled by default. Requires an enabled local user directly in Administrators before any removal. Preserves groups and local accounts. Verifies remaining candidates. Exits 0 when healthy or fixed, 1 when blocked, disabled with drift, or failed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowedSids = @()
$EnableRemediation = $false

$PackageName = 'EnrollingUserAdmin'
$Phase = 'Remediate'
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
function Get-AdminState {
    $members = @(Get-LocalGroupMember -SID $adminSid -ErrorAction Stop)
    $localUsers = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -eq $true })
    $localSids = @($localUsers | ForEach-Object { $_.SID.Value })
    $localAdmins = @($members | Where-Object {
        $_.ObjectClass -eq 'User' -and
        $_.SID.Value -like 'S-1-5-21-*' -and
        $localSids -contains $_.SID.Value
    })
    $targets = @($members | Where-Object {
        $_.ObjectClass -eq 'User' -and
        $_.SID.Value -like 'S-1-12-1-*' -and
        $approved -notcontains $_.SID.Value
    })
    [pscustomobject]@{ Targets = $targets; LocalAdmins = $localAdmins.Count }
}

$removed = 0
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
    $state = Get-AdminState
    if ($state.Targets.Count -eq 0) { Exit-Script 0 'Healthy | Candidates=0' }
    if ($state.LocalAdmins -lt 1) {
        Exit-Script 1 "Blocked | Reason=NoEnabledLocalAdmin; Candidates=$($state.Targets.Count); Removed=0"
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Candidates=$($state.Targets.Count); LocalAdmins=$($state.LocalAdmins); Removed=0"
    }
    foreach ($target in $state.Targets) {
        $current = Get-AdminState
        if ($current.LocalAdmins -lt 1) {
            Exit-Script 1 "Blocked | Reason=NoEnabledLocalAdmin; Removed=$removed"
        }
        $matched = @($current.Targets | Where-Object { $_.SID.Value -eq $target.SID.Value })
        if ($matched.Count -eq 0) { continue }
        Remove-LocalGroupMember -SID $adminSid -Member $matched -Confirm:$false -ErrorAction Stop
        $removed += $matched.Count
    }
    $after = Get-AdminState
    if ($after.Targets.Count -gt 0 -or $after.LocalAdmins -lt 1) {
        Exit-Script 1 "Failed | Removed=$removed; Remaining=$($after.Targets.Count); LocalAdmins=$($after.LocalAdmins)"
    }
    Exit-Script 0 "Fixed | Removed=$removed; Remaining=0; LocalAdmins=$($after.LocalAdmins)"
}
catch { Exit-Script 1 "Error: Failed | Reason=RemediationFailed; Removed=$removed; Type=$($_.Exception.GetType().Name)" }
