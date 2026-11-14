<#
.SYNOPSIS
  Remediation script that removes Chrome and Zoom installs sitting under a user profile.

.DESCRIPTION
  Finds Chrome and Zoom under AppData in every local user profile and runs the uninstall command the app registered for that user. A profile is skipped while the app is running. Uninstall is off by default and runs only when $UninstallPerUserApps is set to $true. Exits 0 when nothing is left to remove, 1 when an uninstall fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$UninstallPerUserApps   = $false
$MountSignedOutProfiles = $true
$MaxProfilesPerRun      = 5
$UninstallTimeoutMs     = 900000
$TargetApps = @(
    [pscustomobject]@{
        Name           = 'Chrome'
        Marker         = 'AppData\Local\Google\Chrome\Application\chrome.exe'
        DisplayPattern = '^Google Chrome$'
        ProcessName    = 'chrome.exe'
    }
    [pscustomobject]@{
        Name           = 'Zoom'
        Marker         = 'AppData\Roaming\Zoom\bin\Zoom.exe'
        DisplayPattern = '^Zoom( Workplace)?(\s*\(.*\))?$'
        ProcessName    = 'zoom.exe'
    }
)

$PackageName = 'PerUserChromeZoom'
$Phase       = 'Remediate'
$LogFile     = Join-Path -Path $env:ProgramData -ChildPath "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-LocalProfile {
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special=False' -ErrorAction Stop)
    foreach ($userProfile in $profiles) {
        if (-not $userProfile.SID) { continue }
        if ($userProfile.SID -notmatch '^S-1-5-21-') { continue }
        if (-not $userProfile.LocalPath) { continue }
        if (-not (Test-Path -LiteralPath $userProfile.LocalPath -PathType Container)) { continue }
        $userProfile
    }
}

function Get-PerUserInstall {
    param($UserProfile)
    $found = @()
    foreach ($app in $TargetApps) {
        $exePath = Join-Path -Path $UserProfile.LocalPath -ChildPath $app.Marker
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { continue }
        $found += [pscustomobject]@{
            Name        = $app.Name
            Sid         = $UserProfile.SID
            ProfilePath = $UserProfile.LocalPath
            ExePath     = $exePath
        }
    }
    $found
}

function Connect-UserHive {
    param([string]$Sid, [string]$ProfilePath, [bool]$AllowMount)
    $loadedPath = 'Registry::HKEY_USERS\' + $Sid
    if (Test-Path -LiteralPath $loadedPath) {
        return [pscustomobject]@{ Path = $loadedPath; MountName = $Sid; Mounted = $false }
    }
    if (-not $AllowMount) { return $null }
    $hiveFile = Join-Path -Path $ProfilePath -ChildPath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $hiveFile -PathType Leaf)) { return $null }
    $mountName = 'IRT_PerUser_' + ($Sid -replace '[^0-9]', '')
    $mountPath = 'Registry::HKEY_USERS\' + $mountName
    if (Test-Path -LiteralPath $mountPath) {
        return [pscustomobject]@{ Path = $mountPath; MountName = $mountName; Mounted = $false }
    }
    $output = & reg.exe load ('HKU\' + $mountName) $hiveFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-IRTLog ('User hive could not be mounted: {0}' -f ($output -join ' ')) 'WARN'
        return $null
    }
    [pscustomobject]@{ Path = $mountPath; MountName = $mountName; Mounted = $true }
}

function Disconnect-UserHive {
    param($Hive)
    if (-not $Hive) { return }
    if (-not $Hive.Mounted) { return }
    $output = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $output = & reg.exe unload ('HKU\' + $Hive.MountName) 2>&1
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 2
    }
    Write-IRTLog ('User hive could not be unmounted: {0}' -f ($output -join ' ')) 'WARN'
}

function Get-UninstallEntry {
    param($Hive, $App, [string]$ProfilePath)
    $roots = @(
        ($Hive.Path + '\Software\Microsoft\Windows\CurrentVersion\Uninstall')
        ($Hive.Path + '\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $props) { continue }
            $displayName = [string]$props.DisplayName
            if ($displayName -notmatch $App.DisplayPattern) { continue }
            $commandText = [string]$props.QuietUninstallString
            if (-not $commandText) { $commandText = [string]$props.UninstallString }
            if (-not $commandText) { continue }
            $inProfile = $false
            foreach ($text in @($commandText, [string]$props.InstallLocation)) {
                if (-not $text) { continue }
                if ($text.IndexOf($ProfilePath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $inProfile = $true }
            }
            if (-not $inProfile) { continue }
            return [pscustomobject]@{ DisplayName = $displayName; Command = $commandText; KeyName = $key.PSChildName }
        }
    }
    return $null
}

function Split-UninstallCommand {
    param([string]$Command)
    $text = $Command.Trim()
    if ($text -match '^"([^"]+)"\s*(.*)$') {
        return [pscustomobject]@{ ExePath = $matches[1]; ArgumentList = $matches[2].Trim() }
    }
    if ($text -match '^(.*?\.exe)(?:\s+(.*))?$') {
        return [pscustomobject]@{ ExePath = $matches[1]; ArgumentList = [string]$matches[2] }
    }
    return $null
}

try {
    $profiles = @(Get-LocalProfile)
    if ($profiles.Count -eq 0) { Exit-Script 0 'NotApplicable | UserProfiles=0' }

    $install = @()
    foreach ($userProfile in $profiles) { $install += @(Get-PerUserInstall -UserProfile $userProfile) }
    if ($install.Count -eq 0) { Exit-Script 0 "Healthy | Profiles=$($profiles.Count); PerUser=0" }

    $counts = @()
    foreach ($app in $TargetApps) {
        $count = @($install | Where-Object { $_.Name -eq $app.Name }).Count
        if ($count -gt 0) { $counts += ('{0}={1}' -f $app.Name, $count) }
    }
    $head = $counts -join '; '

    if (-not $UninstallPerUserApps) {
        Exit-Script 0 "ReportOnly | $head; Profiles=$($profiles.Count); Toggle=UninstallPerUserApps"
    }

    $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)
    $visited   = @{}
    $removed   = 0
    $skipped   = 0
    $failed    = 0
    $remaining = 0
    $reasons   = @()

    foreach ($item in $install) {
        if (-not $visited.ContainsKey($item.ProfilePath)) {
            if ($visited.Count -ge $MaxProfilesPerRun) { $remaining++; continue }
            $visited[$item.ProfilePath] = $true
        }

        $app = @($TargetApps | Where-Object { $_.Name -eq $item.Name })[0]
        $safePath = $item.ExePath.Replace($item.ProfilePath, '<profile>')

        $running = $false
        foreach ($process in $processes) {
            if ($process.Name -ne $app.ProcessName) { continue }
            if (-not $process.ExecutablePath) { continue }
            if ($process.ExecutablePath.IndexOf($item.ProfilePath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $running = $true }
        }
        if ($running) {
            Write-IRTLog ('App is running, profile skipped: {0} at {1}' -f $item.Name, $safePath) 'WARN'
            $skipped++
            continue
        }

        $hive = $null
        try {
            $hive = Connect-UserHive -Sid $item.Sid -ProfilePath $item.ProfilePath -AllowMount $MountSignedOutProfiles
            if (-not $hive) {
                Write-IRTLog ('User registry not available: {0}' -f $safePath) 'WARN'
                $failed++
                $reasons += ('{0}:NoRegistry' -f $item.Name)
                continue
            }
            $entry = Get-UninstallEntry -Hive $hive -App $app -ProfilePath $item.ProfilePath
            if (-not $entry) {
                Write-IRTLog ('No per-user uninstall entry: {0}' -f $safePath) 'WARN'
                $failed++
                $reasons += ('{0}:NoUninstaller' -f $item.Name)
                continue
            }
            $command = Split-UninstallCommand -Command $entry.Command
            if (-not $command) {
                Write-IRTLog ('Uninstall command not understood: {0}' -f $safePath) 'WARN'
                $failed++
                $reasons += ('{0}:BadCommand' -f $item.Name)
                continue
            }
            if (-not (Test-Path -LiteralPath $command.ExePath -PathType Leaf)) {
                Write-IRTLog ('Uninstaller file missing: {0}' -f $safePath) 'WARN'
                $failed++
                $reasons += ('{0}:UninstallerMissing' -f $item.Name)
                continue
            }

            $logCommand = $command.ExePath.Replace($item.ProfilePath, '<profile>')
            Write-IRTLog ('Running uninstaller: {0}' -f $logCommand)

            $startParams = @{
                FilePath    = $command.ExePath
                PassThru    = $true
                WindowStyle = 'Hidden'
                ErrorAction = 'Stop'
            }
            $arguments = [string]$command.ArgumentList
            if ($item.Name -eq 'Chrome' -and $arguments -notmatch '--force-uninstall') { $arguments = ($arguments + ' --force-uninstall').Trim() }
            if ($arguments) { $startParams['ArgumentList'] = $arguments }
            $process = Start-Process @startParams

            if (-not $process.WaitForExit($UninstallTimeoutMs)) {
                Write-IRTLog ('Uninstaller timed out: {0}' -f $safePath) 'WARN'
                $failed++
                $reasons += ('{0}:Timeout' -f $item.Name)
                continue
            }
            $process.WaitForExit()
            $exitCode = $process.ExitCode

            if (Test-Path -LiteralPath $item.ExePath -PathType Leaf) {
                Write-IRTLog ('Uninstaller left the app in place: {0} ExitCode={1}' -f $safePath, $exitCode) 'WARN'
                $failed++
                $reasons += ('{0}:Exit={1}' -f $item.Name, $exitCode)
                continue
            }
            Write-IRTLog ('Per-user install removed: {0}' -f $safePath)
            $removed++
        }
        finally {
            Disconnect-UserHive -Hive $hive
        }
    }

    $tail = 'Removed={0}; Skipped={1}; Failed={2}; Remaining={3}; Profiles={4}' -f $removed, $skipped, $failed, $remaining, $profiles.Count
    if ($failed -gt 0) {
        Exit-Script 1 ('Failed | ' + $head + '; ' + $tail + '; Reasons=' + ($reasons -join ','))
    }
    if ($removed -eq 0) {
        Exit-Script 1 ('Pending | ' + $head + '; ' + $tail + '; Note=nothing removed')
    }
    Exit-Script 0 ('Fixed | ' + $head + '; ' + $tail)
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
