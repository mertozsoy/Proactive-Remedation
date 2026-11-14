<#
.SYNOPSIS
  Remediation script for local user accounts that are missing from the approved list.

.DESCRIPTION
  Disables unapproved local accounts and deletes them when deletion is approved.
  Built-in accounts, the approved list, loaded profiles and the last local
  administrator are protected. Exits 0 when no unapproved account remains enabled,
  1 when an account is blocked or an error occurs.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedAccounts = @()
$ExcludedNames = @('defaultuser0')
$MinimumRid = 1000
$DisableUnapprovedAccounts = $true
$DeleteUnapprovedAccounts = $false
$MaxAccountsPerRun = 5
$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'UnapprovedLocalAccounts'
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

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired' }
    if ($ApprovedAccounts.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=ApprovedListEmpty' }
    if (-not $DisableUnapprovedAccounts -and -not $DeleteUnapprovedAccounts) {
        Exit-Script 1 'Blocked | Reason=NoActionEnabled'
    }

    $approved = @($ApprovedAccounts | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $excluded = @($ExcludedNames | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $unapproved = @()
    foreach ($account in @(Get-LocalUser)) {
        if (-not $account.SID) { continue }
        $sid = $account.SID.Value
        if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { continue }
        if ([int64]($sid.Split('-')[-1]) -lt $MinimumRid) { continue }
        if ($account.PrincipalSource -and [string]$account.PrincipalSource -ne 'Local') { continue }
        if ($excluded -contains $account.Name.ToLowerInvariant()) { continue }
        if ($approved -contains $account.Name.ToLowerInvariant()) { continue }
        $unapproved += $account
    }

    $enabled = @($unapproved | Where-Object { $_.Enabled })
    if ($enabled.Count -eq 0 -and -not $DeleteUnapprovedAccounts) {
        Exit-Script 0 "Healthy | Unapproved=$($unapproved.Count); Enabled=0"
    }
    $targets = $enabled
    if ($DeleteUnapprovedAccounts) { $targets = $unapproved }
    if ($targets.Count -eq 0) { Exit-Script 0 'Healthy | Unapproved=0; Enabled=0' }

    $adminSids = $null
    try { $adminSids = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Where-Object { $_.SID } | ForEach-Object { $_.SID.Value }) }
    catch { $adminSids = $null }
    if ($null -eq $adminSids) { Exit-Script 1 'Blocked | Reason=LocalAdminGroupUnreadable' }

    $targetSids = @($targets | ForEach-Object { $_.SID.Value })
    $usersRoot = [IO.Path]::GetFullPath((Join-Path $env:SystemDrive 'Users')).TrimEnd('\')
    $disabled = 0
    $deleted = 0
    $blocked = 0
    $failed = 0
    foreach ($target in @($targets | Select-Object -First $MaxAccountsPerRun)) {
        $sid = $target.SID.Value
        if ($adminSids -contains $sid) {
            $otherAdmins = @($adminSids | Where-Object { $targetSids -notcontains $_ })
            if ($otherAdmins.Count -eq 0) { $blocked++; continue }
        }
        $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'")
        if (@($profiles | Where-Object { $_.Loaded }).Count -gt 0) { $blocked++; continue }
        try {
            if ($DisableUnapprovedAccounts -and $target.Enabled) {
                Disable-LocalUser -SID $target.SID -ErrorAction Stop
                $disabled++
            }
            if ($DeleteUnapprovedAccounts) {
                foreach ($userProfile in $profiles) {
                    if ($userProfile.Special -or -not $userProfile.LocalPath) { continue }
                    $profilePath = [IO.Path]::GetFullPath($userProfile.LocalPath).TrimEnd('\')
                    if (-not $profilePath.StartsWith($usersRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
                    $registryKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $sid
                    New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null
                    $backupFile = Join-Path $BackupRoot ('UnapprovedLocalAccount_{0}.reg' -f [guid]::NewGuid().ToString('N'))
                    & "$env:SystemRoot\System32\reg.exe" export $registryKey $backupFile /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) { throw 'ProfileRegistryBackupFailed' }
                    $userProfile | Remove-CimInstance -Confirm:$false -ErrorAction Stop
                }
                Remove-LocalUser -SID $target.SID -Confirm:$false -ErrorAction Stop
                $deleted++
            }
        }
        catch { $failed++ }
    }

    $remaining = @(Get-LocalUser | Where-Object {
        $_.SID -and $_.SID.Value -match '^S-1-5-21-\d+-\d+-\d+-\d+$' -and
        [int64]($_.SID.Value.Split('-')[-1]) -ge $MinimumRid -and
        (-not $_.PrincipalSource -or [string]$_.PrincipalSource -eq 'Local') -and
        $excluded -notcontains $_.Name.ToLowerInvariant() -and
        $approved -notcontains $_.Name.ToLowerInvariant()
    })
    $remainingEnabled = @($remaining | Where-Object { $_.Enabled })
    if ($remainingEnabled.Count -eq 0 -and $blocked -eq 0 -and $failed -eq 0) {
        Exit-Script 0 "Fixed | Disabled=$disabled; Deleted=$deleted; Remaining=$($remaining.Count)"
    }
    Exit-Script 1 "Partial | Disabled=$disabled; Deleted=$deleted; Blocked=$blocked; Failed=$failed; RemainingEnabled=$($remainingEnabled.Count)"
}
catch { Exit-Script 1 ('Error: RemediationFailed | HResult={0}' -f $_.Exception.HResult) }
