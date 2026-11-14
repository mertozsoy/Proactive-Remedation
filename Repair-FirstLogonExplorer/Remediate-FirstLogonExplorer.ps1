<#
.SYNOPSIS
  Restarts the current user's Explorer shell once for an eligible new profile.

.DESCRIPTION
  Restart is opt-in because Explorer file operations may be interrupted. Checks shell ownership and session, restarts only the shell process and records completion only after a replacement shell is verified. Exits 0 on success or deferral, 1 on disabled remediation or failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$EnableRemediation = $false
$MaxProfileAgeHours = 48
$MinimumShellAgeMinutes = 5
$RetryCooldownMinutes = 30
$ShellRecoveryTimeoutSeconds = 30

$PackageName = 'FirstLogonExplorer'
$Phase = 'Remediate'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
$StateFile = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\FirstLogonExplorer\State.json'
$ErrorActionPreference = 'Stop'
$stateLock = $null

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $logDirectory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
    catch { return }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 2000) }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-RefreshState {
    if (-not (Test-Path -LiteralPath $StateFile)) { return 'Pending' }
    $record = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
    if ($record.Completed -isnot [bool] -or -not $record.AttemptUtc) { throw 'InvalidState' }
    $attempt = [datetime]::Parse($record.AttemptUtc, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    if ($attempt -gt [datetime]::UtcNow) { throw 'FutureState' }
    if ($record.Completed) { return 'Completed' }
    if (([datetime]::UtcNow - $attempt).TotalMinutes -lt $RetryCooldownMinutes) { return 'Cooldown' }
    return 'Pending'
}

function Get-ExplorerShell {
    $window = [IRTFirstLogonExplorer.NativeMethods]::GetShellWindow()
    if ($window -eq [intptr]::Zero) { return $null }
    [uint32]$shellProcessId = 0
    $thread = [IRTFirstLogonExplorer.NativeMethods]::GetWindowThreadProcessId($window, [ref]$shellProcessId)
    if ($thread -eq 0 -or $shellProcessId -eq 0) { throw 'ShellLookupFailed' }
    $process = Get-Process -Id $shellProcessId -ErrorAction Stop
    if ($process.ProcessName -ne 'explorer' -or $process.SessionId -ne $script:SessionId) { throw 'UnexpectedShell' }
    $instance = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $shellProcessId"
    $owner = Invoke-CimMethod -InputObject $instance -MethodName GetOwnerSid
    if ($owner.ReturnValue -ne 0 -or $owner.Sid -ne $script:UserSid) { throw 'ShellOwnerMismatch' }
    return $process
}

try {
    if ($MaxProfileAgeHours -le 0 -or $MinimumShellAgeMinutes -lt 0 -or $RetryCooldownMinutes -lt 1 -or $ShellRecoveryTimeoutSeconds -lt 10) { throw 'InvalidConfiguration' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $script:UserSid = $identity.User.Value
    $script:SessionId = (Get-Process -Id $PID).SessionId
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($script:SessionId -eq 0 -or $identity.IsSystem -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Exit-Script 0 'NotApplicable | Reason=RequiresUnelevatedUserSession'
    }
    $state = Get-RefreshState
    if ($state -eq 'Completed') { Exit-Script 0 'Healthy | Refresh=Completed; Scope=Profile' }
    if ($state -eq 'Cooldown') { Exit-Script 0 'Deferred | Reason=RetryCooldown; Refresh=Pending' }
    $profileAge = ([datetime]::UtcNow - (Get-Item -LiteralPath $env:USERPROFILE).CreationTimeUtc).TotalHours
    if ($profileAge -lt 0 -or $profileAge -gt $MaxProfileAgeHours) {
        Exit-Script 0 'NotApplicable | Reason=OutsideNewProfileWindow'
    }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace IRTFirstLogonExplorer {
    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern IntPtr GetShellWindow();
        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    }
}
'@
    $shell = Get-ExplorerShell
    if ($null -eq $shell) { Exit-Script 0 'NotApplicable | Reason=NoExplorerShell' }
    if (([datetime]::UtcNow - $shell.StartTime.ToUniversalTime()).TotalMinutes -lt $MinimumShellAgeMinutes) {
        Exit-Script 0 'Deferred | Reason=ShellGracePeriod; Refresh=Pending'
    }
    if (-not $EnableRemediation) { Exit-Script 1 'Blocked | Refresh=Pending; EnableRemediation=False' }
    $explorerPath = Join-Path $env:WINDIR 'explorer.exe'
    if (-not (Test-Path -LiteralPath $explorerPath -PathType Leaf)) { throw 'ExplorerBinaryMissing' }
    $stateDirectory = Split-Path -Parent $StateFile
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $stateLock = [IO.File]::Open((Join-Path $stateDirectory 'Refresh.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $state = Get-RefreshState
    if ($state -eq 'Completed') { Exit-Script 0 'Healthy | Refresh=Completed; Scope=Profile' }
    if ($state -eq 'Cooldown') { Exit-Script 0 'Deferred | Reason=RetryCooldown; Refresh=Pending' }
    $confirmedShell = Get-ExplorerShell
    if ($null -eq $confirmedShell -or $confirmedShell.Id -ne $shell.Id -or $confirmedShell.StartTime -ne $shell.StartTime) {
        Exit-Script 0 'Deferred | Reason=ShellChanged; Refresh=Pending'
    }
    $attemptUtc = [datetime]::UtcNow.ToString('o')
    @{ Completed = $false; AttemptUtc = $attemptUtc } | ConvertTo-Json -Compress | Set-Content -LiteralPath $StateFile -Encoding UTF8
    $oldStartTime = $shell.StartTime.ToUniversalTime()
    Stop-Process -InputObject $confirmedShell -Force -ErrorAction Stop
    if (-not $confirmedShell.WaitForExit(10000)) { Exit-Script 1 'Failed | Reason=OldShellStillRunning; Refresh=Pending' }
    Start-Sleep -Seconds 3
    $replacement = Get-ExplorerShell
    if ($null -eq $replacement) {
        Start-Process -FilePath $explorerPath -WorkingDirectory $env:WINDIR -ErrorAction Stop
    }
    $deadline = [datetime]::UtcNow.AddSeconds($ShellRecoveryTimeoutSeconds)
    $verified = $false
    do {
        Start-Sleep -Seconds 2
        $replacement = Get-ExplorerShell
        if ($null -ne $replacement -and $replacement.StartTime.ToUniversalTime() -gt $oldStartTime) {
            Start-Sleep -Seconds 2
            $stableShell = Get-ExplorerShell
            if ($null -ne $stableShell -and $stableShell.Id -eq $replacement.Id -and $stableShell.StartTime -eq $replacement.StartTime) {
                $verified = $true
                break
            }
        }
    } while ([datetime]::UtcNow -lt $deadline)
    if (-not $verified) { Exit-Script 1 'Failed | Reason=ReplacementShellNotVerified; Refresh=Pending' }
    @{ Completed = $true; AttemptUtc = $attemptUtc } | ConvertTo-Json -Compress | Set-Content -LiteralPath $StateFile -Encoding UTF8
    if ((Get-RefreshState) -ne 'Completed') { Exit-Script 1 'Failed | Reason=CompletionNotSaved; Refresh=Pending' }
    Exit-Script 0 'Fixed | Refresh=Completed; Shell=Verified; Scope=Profile'
}
catch { Exit-Script 1 "Error: Type=$($_.Exception.GetType().Name); Action=Investigate" }
finally {
    if ($null -ne $stateLock) { $stateLock.Dispose() }
}
