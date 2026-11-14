<#
.SYNOPSIS
  Remediation script for the local account managed by Windows LAPS.

.DESCRIPTION
  Creates the account named in the Windows LAPS policy with a random password, enables it and adds it to the local Administrators group, then asks LAPS to process its policy. Exits 0 if the account is ready, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableBuiltInAdmin = $false
$PasswordLength     = 32

$PackageName = 'LapsAccount'
$Phase       = 'Remediate'
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

function New-RandomSecret { param([int]$Length)
    $chars  = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%*-_=+'
    $rng    = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes  = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    $secret = New-Object System.Security.SecureString
    foreach ($b in $bytes) { $secret.AppendChar($chars[$b % $chars.Length]) }
    $rng.Dispose()
    return $secret
}

try {
    $policy = Get-LapsPolicy
    if (-not $policy -or $policy.Backup -eq 0) { Exit-Script 0 'NotApplicable | LapsPolicy=None' }
    if ($policy.AutoManaged) { Exit-Script 0 "NotApplicable | LapsPolicy=$($policy.Source); Mode=Automatic" }

    $actions = @()
    if ([string]::IsNullOrWhiteSpace($policy.AccountName)) {
        $builtIn = Get-LocalUser | Where-Object { $_.SID.Value -like 'S-1-5-21-*-500' } | Select-Object -First 1
        if ($EnableBuiltInAdmin -and -not $builtIn.Enabled) {
            Enable-LocalUser -SID $builtIn.SID -ErrorAction Stop
            $actions += 'EnabledBuiltIn'
        }
        $builtIn = Get-LocalUser -SID $builtIn.SID
        if (Get-Command Invoke-LapsPolicyProcessing -ErrorAction SilentlyContinue) { Invoke-LapsPolicyProcessing; $actions += 'LapsProcessed' }
        $summary = "Account=BuiltIn; Enabled=$($builtIn.Enabled); Actions=$($actions -join ',')"
        if ($EnableBuiltInAdmin -and -not $builtIn.Enabled) { Exit-Script 1 "Failed | $summary" }
        Exit-Script 0 "Remediated | $summary"
    }

    $name = $policy.AccountName
    $user = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if (-not $user) {
        $secret = New-RandomSecret -Length $PasswordLength
        $user = New-LocalUser -Name $name -Password $secret -PasswordNeverExpires -AccountNeverExpires -Description 'Local administrator managed by Windows LAPS' -ErrorAction Stop
        $secret.Dispose()
        $actions += 'Created'
        Write-IRTLog "Created local account $name"
    }
    if (-not $user.Enabled) {
        Enable-LocalUser -SID $user.SID -ErrorAction Stop
        $actions += 'Enabled'
    }
    if (-not (Test-LocalAdminMember -Sid $user.SID)) {
        Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $user.SID -ErrorAction Stop
        $actions += 'AddedToAdmins'
    }

    if (Get-Command Invoke-LapsPolicyProcessing -ErrorAction SilentlyContinue) {
        Invoke-LapsPolicyProcessing
        $actions += 'LapsProcessed'
    }

    $user = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    $ok = $user -and $user.Enabled -and (Test-LocalAdminMember -Sid $user.SID)
    $summary = "LapsPolicy=$($policy.Source); Account=$name; Actions=$($actions -join ',')"
    if ($ok) { Exit-Script 0 "Remediated | $summary" }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
