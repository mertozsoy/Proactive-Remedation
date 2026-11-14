<#
.SYNOPSIS
  Detection script for the defaultuser0 account and profile left after provisioning.

.DESCRIPTION
  Checks the exact local account and its registered profile. Exits 1 for leftovers
  or inspection errors, 0 when absent or Windows setup is not complete.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedProfilePath = Join-Path $env:SystemDrive 'Users\defaultuser0'

$PackageName = 'DefaultUserZero'
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
    $blocked = @($profiles | Where-Object { $_.Loaded -or $_.Special }).Count
    Exit-Script 1 "Drift | Accounts=$($account.Count); Profiles=$($profiles.Count); FolderPresent=$folderPresent; ProtectedProfiles=$blocked"
}
catch { Exit-Script 1 ('Error: InspectionFailed | HResult={0}' -f $_.Exception.HResult) }
