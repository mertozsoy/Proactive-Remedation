<#
.SYNOPSIS
  Remediation script for the defaultuser0 account and profile left after provisioning.

.DESCRIPTION
  Removes only the exact local account and a verified unloaded profile after setup.
  Destructive cleanup is disabled by default. Exits 0 after verified cleanup or when
  not applicable, 1 when approval is missing, cleanup is blocked, or an error occurs.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$ExpectedProfilePath = Join-Path $env:SystemDrive 'Users\defaultuser0'
$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'DefaultUserZero'
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
    $setup = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -Name ImageState
    if ($setup.ImageState -ne 'IMAGE_STATE_COMPLETE') { Exit-Script 0 'NotApplicable | Reason=SetupNotComplete' }

    $users = @(Get-LocalUser)
    $account = @($users | Where-Object { $_.Name -eq 'defaultuser0' })
    $accountSid = ''
    if ($account.Count -eq 1) { $accountSid = $account[0].SID.Value }
    $allProfiles = @(Get-CimInstance -ClassName Win32_UserProfile)
    $profiles = @($allProfiles | Where-Object {
        ($accountSid -ne '' -and $_.SID -eq $accountSid) -or
        ($_.LocalPath -and [IO.Path]::GetFileName($_.LocalPath.TrimEnd('\')) -eq 'defaultuser0')
    })
    $folderPresent = Test-Path -LiteralPath $ExpectedProfilePath
    if ($account.Count -eq 0 -and $profiles.Count -eq 0 -and -not $folderPresent) {
        Exit-Script 0 'Healthy | Accounts=0; Profiles=0; FolderPresent=False'
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Accounts=$($account.Count); Profiles=$($profiles.Count); Reason=EnableRemediationFalse"
    }
    if ($account.Count -gt 1 -or $profiles.Count -gt 1) { Exit-Script 1 'Blocked | Reason=AmbiguousIdentity' }
    if ($account.Count -eq 1 -and ($accountSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or
        [int64]($accountSid.Split('-')[-1]) -lt 1000)) {
        Exit-Script 1 'Blocked | Reason=ProtectedAccountSid'
    }
    if ($folderPresent -and $profiles.Count -eq 0) { Exit-Script 1 'Blocked | Reason=UnregisteredFolderNeedsReview' }
    $otherProfiles = @($allProfiles | Where-Object {
        -not $_.Special -and $_.SID -ne $accountSid -and
        $_.LocalPath -and [IO.Path]::GetFileName($_.LocalPath.TrimEnd('\')) -ne 'defaultuser0'
    })
    if ($otherProfiles.Count -eq 0) { Exit-Script 1 'Blocked | Reason=NoOtherUserProfile' }

    foreach ($targetProfile in $profiles) {
        if ($targetProfile.Loaded -or $targetProfile.Special) { Exit-Script 1 'Blocked | Reason=ProfileInUseOrSpecial' }
        if ($targetProfile.SID -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { Exit-Script 1 'Blocked | Reason=UnexpectedProfileSid' }
        if ([int64]($targetProfile.SID.Split('-')[-1]) -lt 1000) { Exit-Script 1 'Blocked | Reason=ProtectedProfileSid' }
        if (-not $targetProfile.LocalPath -or [IO.Path]::GetFullPath($targetProfile.LocalPath).TrimEnd('\') -ne [IO.Path]::GetFullPath($ExpectedProfilePath).TrimEnd('\')) {
            Exit-Script 1 'Blocked | Reason=UnexpectedProfilePath'
        }
        $owners = @($users | Where-Object { $_.SID.Value -eq $targetProfile.SID })
        if (($accountSid -ne '' -and $targetProfile.SID -ne $accountSid) -or
            @($owners | Where-Object { $_.Name -ne 'defaultuser0' }).Count -gt 0) {
            Exit-Script 1 'Blocked | Reason=ProfileIdentityMismatch'
        }
        if ($accountSid -eq '') {
            $identityResolved = $false
            try {
                $profileIdentity = New-Object System.Security.Principal.SecurityIdentifier($targetProfile.SID)
                $null = $profileIdentity.Translate([System.Security.Principal.NTAccount])
                $identityResolved = $true
            }
            catch [System.Security.Principal.IdentityNotMappedException] { }
            if ($identityResolved) { Exit-Script 1 'Blocked | Reason=ProfileOwnedByExistingAccount' }
        }
        if ($folderPresent) {
            $directory = Get-Item -LiteralPath $ExpectedProfilePath -Force
            $parent = Get-Item -LiteralPath (Split-Path -Path $ExpectedProfilePath -Parent) -Force
            if (-not $directory.PSIsContainer -or
                ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Exit-Script 1 'Blocked | Reason=UnsafeProfileDirectory'
            }
        }
        $registryKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $targetProfile.SID
        $null = New-Item -Path $BackupRoot -ItemType Directory -Force
        $backupFile = Join-Path $BackupRoot ('DefaultUserZero_{0}.reg' -f [guid]::NewGuid().ToString('N'))
        & "$env:SystemRoot\System32\reg.exe" export $registryKey $backupFile /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) {
            Exit-Script 1 'Failed | Reason=ProfileRegistryBackupFailed'
        }
        $freshProfile = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($targetProfile.SID)'")
        if ($freshProfile.Count -ne 1 -or $freshProfile[0].Loaded -or $freshProfile[0].Special -or
            $freshProfile[0].LocalPath -ne $targetProfile.LocalPath) {
            Exit-Script 1 'Blocked | Reason=ProfileStateChanged'
        }
        $freshProfile[0] | Remove-CimInstance -Confirm:$false -ErrorAction Stop
        if (@(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($targetProfile.SID)'").Count -ne 0 -or
            (Test-Path -LiteralPath $ExpectedProfilePath)) {
            Exit-Script 1 'Failed | Reason=ProfileRemovalIncomplete'
        }
    }
    if ($account.Count -eq 1) {
        $freshAccount = @(Get-LocalUser | Where-Object { $_.Name -eq 'defaultuser0' })
        if ($freshAccount.Count -ne 1 -or $freshAccount[0].SID.Value -ne $accountSid) {
            Exit-Script 1 'Blocked | Reason=AccountIdentityChanged'
        }
        if (@(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$accountSid'").Count -gt 0) {
            Exit-Script 1 'Blocked | Reason=ProfileReappeared'
        }
        Remove-LocalUser -SID $account[0].SID -Confirm:$false -ErrorAction Stop
    }
    $remainingAccount = @(Get-LocalUser | Where-Object { $_.Name -eq 'defaultuser0' })
    $remainingProfile = @(Get-CimInstance -ClassName Win32_UserProfile | Where-Object {
        ($accountSid -ne '' -and $_.SID -eq $accountSid) -or
        ($_.LocalPath -and [IO.Path]::GetFileName($_.LocalPath.TrimEnd('\')) -eq 'defaultuser0')
    })
    if ($remainingAccount.Count -gt 0 -or $remainingProfile.Count -gt 0 -or (Test-Path -LiteralPath $ExpectedProfilePath)) {
        Exit-Script 1 'Failed | Reason=VerificationFailed'
    }
    Exit-Script 0 "Fixed | AccountsRemoved=$($account.Count); ProfilesRemoved=$($profiles.Count); FolderPresent=False"
}
catch { Exit-Script 1 ('Error: CleanupFailed | HResult={0}' -f $_.Exception.HResult) }
