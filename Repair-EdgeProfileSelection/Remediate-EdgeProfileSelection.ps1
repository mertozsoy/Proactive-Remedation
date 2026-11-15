<#
.SYNOPSIS
  Remediation script for Microsoft Edge profile selection and pinned shortcut targets.

.DESCRIPTION
  Rewrites the profile argument on user shortcuts that launch msedge.exe so they open the expected Edge profile. Saves a copy of every changed shortcut before writing. Optionally writes the per-user EdgeDefaultProfileEnabled policy when the setting is not managed by machine policy. Exits 0 only when the expected profile exists and no shortcut or user policy points elsewhere.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedProfileDirectory = 'Default'
$ScanTaskbar = $true
$ScanStartMenu = $true
$ScanDesktop = $true
$SetDefaultProfilePolicy = $false

$PackageName = 'EdgeProfileSelection'
$Phase = 'Remediate'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
$BackupDir = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup\EdgeProfile'
$PolicyPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'
function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null }
        Add-Content -LiteralPath $LogFile -Value ('{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}
function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-EdgeProfileState {
    $localStatePath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Local State'
    if (-not (Test-Path -LiteralPath $localStatePath)) { return $null }
    $raw = Get-Content -LiteralPath $localStatePath -Raw -ErrorAction Stop
    $localState = $raw | ConvertFrom-Json -ErrorAction Stop
    $directories = @()
    if ($null -ne $localState.profile -and $null -ne $localState.profile.info_cache) {
        $directories = @($localState.profile.info_cache.PSObject.Properties.Name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    [pscustomobject]@{
        Directories = $directories
        LastUsed = [string]$localState.profile.last_used
    }
}
function Get-EdgeShortcutFile {
    $paths = @()
    if ($ScanTaskbar) {
        $taskbar = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        if (Test-Path -LiteralPath $taskbar) {
            $paths += @(Get-ChildItem -LiteralPath $taskbar -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    if ($ScanStartMenu) {
        $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        if (Test-Path -LiteralPath $startMenu) {
            $paths += @(Get-ChildItem -LiteralPath $startMenu -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    if ($ScanDesktop) {
        $desktop = Join-Path $env:USERPROFILE 'Desktop'
        if (Test-Path -LiteralPath $desktop) {
            $paths += @(Get-ChildItem -LiteralPath $desktop -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    return @($paths | Sort-Object -Unique)
}
function Get-EdgeShortcutState {
    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($file in @(Get-EdgeShortcutFile)) {
            try {
                $shortcut = $shell.CreateShortcut($file)
                $target = [string]$shortcut.TargetPath
                if ($target -notmatch '(?i)\\msedge(?:_proxy)?\.exe$') { continue }
                $arguments = [string]$shortcut.Arguments
                $profileDirectory = ''
                $match = [regex]::Match($arguments, '(?i)--profile-directory=(?:"([^"]*)"|(\S+))')
                if ($match.Success) {
                    if ($match.Groups[1].Success) { $profileDirectory = $match.Groups[1].Value } else { $profileDirectory = $match.Groups[2].Value }
                }
                $writable = $file.StartsWith($env:APPDATA, [System.StringComparison]::OrdinalIgnoreCase)
                $scope = 'User'
                if (-not $writable) { $scope = 'Machine' }
                [pscustomobject]@{
                    Path = $file
                    Name = [System.IO.Path]::GetFileName($file)
                    Arguments = $arguments
                    Profile = $profileDirectory
                    Scope = $scope
                    Writable = $writable
                }
            } catch {
                continue
            }
        }
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}
function Get-EdgePolicyState {
    param([string]$Expected)
    $machineValue = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name EdgeDefaultProfileEnabled -ErrorAction SilentlyContinue).EdgeDefaultProfileEnabled
    if ($null -ne $machineValue) {
        if ([string]$machineValue -eq $Expected) { return 'MachineSet' }
        return 'MachineWrong'
    }
    $userValue = (Get-ItemProperty -LiteralPath 'HKCU:\SOFTWARE\Policies\Microsoft\Edge' -Name EdgeDefaultProfileEnabled -ErrorAction SilentlyContinue).EdgeDefaultProfileEnabled
    if ($null -ne $userValue) {
        if ([string]$userValue -eq $Expected) { return 'UserSet' }
        return 'UserWrong'
    }
    return 'Missing'
}
function Get-EdgeState {
    $profiles = Get-EdgeProfileState
    if ($null -eq $profiles) { return $null }
    $shortcuts = @(Get-EdgeShortcutState)
    $policy = Get-EdgePolicyState -Expected $ExpectedProfileDirectory
    $wrong = @($shortcuts | Where-Object { $_.Profile -ne $ExpectedProfileDirectory })
    $reasons = @()
    if (-not ($profiles.Directories -contains $ExpectedProfileDirectory)) { $reasons += 'ProfileMissing' }
    if ($wrong.Count -gt 0) { $reasons += 'ShortcutWrong' }
    if ($policy -eq 'UserWrong') { $reasons += 'UserPolicyWrong' }
    if ($policy -eq 'MachineWrong') { $reasons += 'MachinePolicyWrong' }
    [pscustomobject]@{
        Profiles = $profiles
        Shortcuts = $shortcuts
        Wrong = $wrong
        Policy = $policy
        Reasons = $reasons
        Summary = ('Expected={0}; Profiles={1}; Shortcuts={2}; Wrong={3}; Policy={4}' -f $ExpectedProfileDirectory, $profiles.Directories.Count, $shortcuts.Count, $wrong.Count, $policy)
    }
}
function Set-ProfileArgument {
    param([string]$Arguments, [string]$ProfileName)
    $replacement = '--profile-directory="{0}"' -f $ProfileName
    if ($Arguments -match '(?i)--profile-directory=') {
        return [regex]::Replace($Arguments, '(?i)--profile-directory=(?:"[^"]*"|[^\s"]+)', $replacement)
    }
    if ([string]::IsNullOrWhiteSpace($Arguments)) { return $replacement }
    return ('{0} {1}' -f $Arguments.Trim(), $replacement)
}
function Copy-ShortcutBackup {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force -ErrorAction Stop | Out-Null }
    $safeName = [System.IO.Path]::GetFileNameWithoutExtension($Path) -replace '[^A-Za-z0-9._-]', '_'
    $destination = Join-Path $BackupDir ('{0}_{1}.lnk' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), $safeName)
    Copy-Item -LiteralPath $Path -Destination $destination -Force -ErrorAction Stop
    Write-IRTLog "Shortcut backup written"
}
function Set-ShortcutArguments {
    param([string]$Path, [string]$Arguments)
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $null
    try {
        $shortcut = $shell.CreateShortcut($Path)
        $shortcut.Arguments = $Arguments
        $shortcut.Save()
    } finally {
        if ($null -ne $shortcut) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem -or [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        Exit-Script 0 'NotApplicable | Context=NonUserSession'
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedProfileDirectory) -or $ExpectedProfileDirectory -match '[\\/:*?"<>|]') {
        Exit-Script 1 'Failed | Reason=InvalidExpectedProfileDirectory'
    }
    $state = Get-EdgeState
    if ($null -eq $state) { Exit-Script 0 'NotApplicable | Reason=EdgeUserDataNotFound' }
    if ($state.Reasons -contains 'ProfileMissing') {
        Exit-Script 1 "Failed | $($state.Summary); Reason=ExpectedProfileNotInEdge"
    }
    if ($state.Reasons -contains 'MachinePolicyWrong') {
        Exit-Script 1 "Blocked | $($state.Summary); Action=None"
    }

    $changed = 0
    $failed = 0
    $skipped = 0
    foreach ($item in $state.Wrong) {
        if (-not $item.Writable) {
            $skipped++
            continue
        }
        try {
            Copy-ShortcutBackup -Path $item.Path
            $newArguments = Set-ProfileArgument -Arguments $item.Arguments -ProfileName $ExpectedProfileDirectory
            Set-ShortcutArguments -Path $item.Path -Arguments $newArguments
            $changed++
        } catch {
            $failed++
            Write-IRTLog "Shortcut update failed for $($item.Name)" 'WARN'
        }
    }

    $policyAction = 'Disabled'
    if ($SetDefaultProfilePolicy -and ($state.Policy -eq 'Missing' -or $state.Policy -eq 'UserWrong')) {
        if (-not (Test-Path -LiteralPath $PolicyPath)) { New-Item -Path $PolicyPath -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $PolicyPath -Name 'EdgeDefaultProfileEnabled' -PropertyType String -Value $ExpectedProfileDirectory -Force -ErrorAction Stop | Out-Null
        $policyAction = 'UserSet'
        Write-IRTLog 'Per-user EdgeDefaultProfileEnabled policy written'
    }

    $verify = Get-EdgeState
    if ($null -eq $verify) { Exit-Script 1 'Failed | Reason=EdgeUserDataUnreadable' }
    $summary = "Expected=$ExpectedProfileDirectory; Shortcuts=$($verify.Shortcuts.Count); Wrong=$($verify.Wrong.Count); Changed=$changed; Failed=$failed; Skipped=$skipped; Policy=$($verify.Policy); PolicyAction=$policyAction; Backup=Saved"
    if ($verify.Reasons.Count -eq 0) { Exit-Script 0 "Fixed | $summary" }
    if ($failed -gt 0 -or $skipped -gt 0) { Exit-Script 1 "Partial | $summary; Reason=$($verify.Reasons -join ',')" }
    Exit-Script 1 "Failed | $summary; Reason=$($verify.Reasons -join ',')"
} catch { Exit-Script 1 ('Error: RemediationFailed | HResult={0}' -f $_.Exception.HResult) }
