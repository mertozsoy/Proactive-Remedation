<#
.SYNOPSIS
  Detection script for the local account managed by Windows LAPS.

.DESCRIPTION
  Reads the active Windows LAPS policy and checks that the target account exists, is enabled and is a member of the local Administrators group. Exits 1 if the account is missing, disabled or not an administrator.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableBuiltInAdmin = $false

$PackageName = 'LapsAccount'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-LapsPolicy {
    $roots = [ordered]@{
        'CSP' = 'HKLM:\SOFTWARE\Microsoft\Policies\LAPS'
        'GPO' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS'
    }
    foreach ($source in $roots.Keys) {
        $item = Get-ItemProperty -LiteralPath $roots[$source] -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        $values = @($item.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
        if ($values.Count -eq 0) { continue }
        return [pscustomobject]@{
            Source        = $source
            Backup        = [int]$item.BackupDirectory
            AccountName   = [string]$item.AdministratorAccountName
            AutoManaged   = ([int]$item.AutomaticAccountManagementEnabled -eq 1)
        }
    }
    return $null
}

function Test-LocalAdminMember { param([System.Security.Principal.SecurityIdentifier]$Sid)
    $adminSid  = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
    $groupName = $adminSid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
    $group     = [ADSI]"WinNT://./$groupName,group"
    foreach ($member in @($group.Invoke('Members'))) {
        $bytes = $member.GetType().InvokeMember('objectSid', 'GetProperty', $null, $member, $null)
        if ($bytes -and (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Equals($Sid)) { return $true }
    }
    return $false
}

try {
    $policy = Get-LapsPolicy
    if (-not $policy -or $policy.Backup -eq 0) { Exit-Script 0 'NotApplicable | LapsPolicy=None' }
    if ($policy.AutoManaged) { Exit-Script 0 "NotApplicable | LapsPolicy=$($policy.Source); Mode=Automatic" }

    if ([string]::IsNullOrWhiteSpace($policy.AccountName)) {
        $builtIn = Get-LocalUser | Where-Object { $_.SID.Value -like 'S-1-5-21-*-500' } | Select-Object -First 1
        $summary = "LapsPolicy=$($policy.Source); Account=BuiltIn; Enabled=$($builtIn.Enabled)"
        if ($EnableBuiltInAdmin -and -not $builtIn.Enabled) { Exit-Script 1 "Unhealthy (BuiltInDisabled) | $summary" }
        Exit-Script 0 "Healthy | $summary"
    }

    $issues = @()
    $user = Get-LocalUser -Name $policy.AccountName -ErrorAction SilentlyContinue
    if (-not $user) { $issues += 'Missing' }
    else {
        if (-not $user.Enabled) { $issues += 'Disabled' }
        if (-not (Test-LocalAdminMember -Sid $user.SID)) { $issues += 'NotAdmin' }
    }

    $summary = "LapsPolicy=$($policy.Source); Account=$($policy.AccountName); Backup=$($policy.Backup)"
    if ($issues) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
