<#
.SYNOPSIS
  Remediation script that refreshes a missing or stale primary refresh token.

.DESCRIPTION
  Schedules a PRT refresh with dsregcmd /refreshprt for the signed-in user, waits for the token to appear, and verifies the update time. Optionally locks the workstation to force the refresh. Exits 0 if the token is healthy again, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$DsregCmdPath            = Join-Path $env:SystemRoot 'System32\dsregcmd.exe'
$MaxPrtAgeHours          = 4
$WaitSeconds             = 90
$PollIntervalSeconds     = 15
$LockWorkstationToRefresh = $false

$PackageName = 'PrimaryRefreshToken'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-DsregField { param([string]$Text, [string]$Name)
    $pattern = '(?im)^[ \t]*' + [regex]::Escape($Name) + '[ \t]*:[ \t]*(\S.*?)[ \t]*$'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function ConvertFrom-DsregTime { param([string]$Value)
    if (-not $Value) { return $null }
    $clean = $Value -replace '\s*UTC\s*$', ''
    $formats = @('yyyy-MM-dd HH:mm:ss.fff', 'yyyy-MM-dd HH:mm:ss')
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($clean, $formats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return [datetime]::SpecifyKind($parsed, 'Utc')
    }
    return $null
}

function Format-PrtTime { param($Value)
    if (-not $Value) { return 'Never' }
    return $Value.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-PrtSnapshot {
    $text  = (& $DsregCmdPath /status 2>$null) -join "`n"
    $state = [pscustomobject]@{
        AzureAdJoined = Get-DsregField -Text $text -Name 'AzureAdJoined'
        DomainJoined  = Get-DsregField -Text $text -Name 'DomainJoined'
        Prt           = Get-DsregField -Text $text -Name 'AzureAdPrt'
        UpdateTime    = ConvertFrom-DsregTime -Value (Get-DsregField -Text $text -Name 'AzureAdPrtUpdateTime')
        ExpiryTime    = ConvertFrom-DsregTime -Value (Get-DsregField -Text $text -Name 'AzureAdPrtExpiryTime')
        Attempt       = Get-DsregField -Text $text -Name 'Attempt Status'
        AgeHours      = $null
        ExpiresInHours = $null
        State         = 'Unknown'
    }
    if ($state.AzureAdJoined -ne 'YES' -and $state.DomainJoined -ne 'YES') { $state.State = 'NotApplicable'; return $state }
    if (-not $state.Prt) { return $state }
    if ($state.Prt -ne 'YES') { $state.State = 'Missing'; return $state }
    if ($state.UpdateTime) {
        $state.AgeHours = [math]::Round(([datetime]::UtcNow - $state.UpdateTime).TotalHours, 1)
    }
    if ($state.ExpiryTime) {
        $state.ExpiresInHours = [math]::Round(($state.ExpiryTime - [datetime]::UtcNow).TotalHours, 1)
        if ($state.ExpiryTime -lt [datetime]::UtcNow) { $state.State = 'Expired'; return $state }
    }
    if ($null -ne $state.AgeHours -and $state.AgeHours -gt $MaxPrtAgeHours) { $state.State = 'Stale'; return $state }
    $state.State = 'Healthy'
    return $state
}

function Invoke-LockWorkstation {
    if (-not ('IRTNative' -as [type])) {
        Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class IRTNative { [DllImport("user32.dll")] public static extern bool LockWorkStation(); }' -ErrorAction Stop
    }
    return [IRTNative]::LockWorkStation()
}

try {
    if (-not (Test-Path -LiteralPath $DsregCmdPath)) { Exit-Script 0 'NotApplicable | Dsregcmd=Missing' }

    $prt = Get-PrtSnapshot
    if ($prt.State -eq 'NotApplicable') { Exit-Script 0 "NotApplicable | AzureAdJoined=$($prt.AzureAdJoined); DomainJoined=$($prt.DomainJoined)" }
    if ($prt.State -eq 'Unknown') { Exit-Script 0 'Unknown | AzureAdPrt=Absent; Action=None' }
    if ($prt.State -eq 'Healthy') { Exit-Script 0 "Healthy | AzureAdPrt=$($prt.Prt); AgeHours=$($prt.AgeHours); Action=None" }

    $previousState = $prt.State
    $started       = Get-Date
    Write-IRTLog "Refresh requested for state $previousState"

    $refreshOutput = (& $DsregCmdPath /refreshprt 2>&1 | Out-String).Trim()
    $refreshCode   = $LASTEXITCODE
    Write-IRTLog "dsregcmd /refreshprt exit $refreshCode length $($refreshOutput.Length)"

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $prt = Get-PrtSnapshot
    while ($prt.State -ne 'Healthy' -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollIntervalSeconds
        $prt = Get-PrtSnapshot
    }

    $lockUsed = $false
    if ($prt.State -ne 'Healthy' -and $LockWorkstationToRefresh) {
        try {
            $lockUsed = [bool](Invoke-LockWorkstation)
            Write-IRTLog "Workstation lock returned $lockUsed"
            Start-Sleep -Seconds $PollIntervalSeconds
            $prt = Get-PrtSnapshot
        }
        catch { Write-IRTLog "Lock failed: $($_.Exception.Message)" 'WARN' }
    }

    $waited = [int]((Get-Date) - $started).TotalSeconds
    if ($prt.State -eq 'Healthy') {
        Exit-Script 0 "Fixed | AzureAdPrt=$($prt.Prt); AgeHours=$($prt.AgeHours); Was=$previousState; Refresh=refreshprt; Waited=$($waited)s; LockUsed=$lockUsed"
    }
    Exit-Script 1 "Failed | AzureAdPrt=$($prt.Prt); Was=$previousState; Attempt=$($prt.Attempt); LastUpdate=$(Format-PrtTime $prt.UpdateTime); RefreshExit=$refreshCode; Waited=$($waited)s; LockUsed=$lockUsed"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
