<#
.SYNOPSIS
  Detects a pending one-time Explorer refresh in a new user profile.

.DESCRIPTION
  Uses profile directory age as an eligibility heuristic, not proof of first logon or policy completion. Exits 1 for a pending refresh, 0 for completed, deferred or inapplicable profiles.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MaxProfileAgeHours = 48
$MinimumShellAgeMinutes = 5
$RetryCooldownMinutes = 30

$PackageName = 'FirstLogonExplorer'
$Phase = 'Detect'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
$StateFile = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\FirstLogonExplorer\State.json'
$ErrorActionPreference = 'Stop'

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
    if ($MaxProfileAgeHours -le 0 -or $MinimumShellAgeMinutes -lt 0 -or $RetryCooldownMinutes -lt 1) { throw 'InvalidConfiguration' }
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
    Exit-Script 1 'Drift | Refresh=Pending; Scope=Profile; Eligibility=ProfileAgeHeuristic'
}
catch { Exit-Script 1 "Error: Type=$($_.Exception.GetType().Name); Action=Investigate" }
