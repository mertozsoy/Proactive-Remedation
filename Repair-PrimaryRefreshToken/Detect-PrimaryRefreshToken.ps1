<#
.SYNOPSIS
  Detection script for a missing or stale primary refresh token.

.DESCRIPTION
  Reads the SSO state that dsregcmd reports for the signed-in user. Exits 1 if AzureAdPrt is not YES, if the token is expired, or if the last update is older than $MaxPrtAgeHours. Exits 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$DsregCmdPath   = Join-Path $env:SystemRoot 'System32\dsregcmd.exe'
$MaxPrtAgeHours = 4

$PackageName = 'PrimaryRefreshToken'
$Phase       = 'Detect'
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

try {
    if (-not (Test-Path -LiteralPath $DsregCmdPath)) { Exit-Script 0 'NotApplicable | Dsregcmd=Missing' }

    $prt = Get-PrtSnapshot
    $age = 'Unknown'
    if ($null -ne $prt.AgeHours) { $age = $prt.AgeHours }
    Write-IRTLog "State=$($prt.State) Prt=$($prt.Prt) AgeHours=$age Attempt=$($prt.Attempt)"

    if ($prt.State -eq 'NotApplicable') { Exit-Script 0 "NotApplicable | AzureAdJoined=$($prt.AzureAdJoined); DomainJoined=$($prt.DomainJoined)" }
    if ($prt.State -eq 'Unknown') { Exit-Script 0 'Unknown | AzureAdPrt=Absent; Action=None' }

    if ($prt.State -eq 'Missing') {
        Exit-Script 1 "MissingPRT | AzureAdPrt=$($prt.Prt); LastUpdate=$(Format-PrtTime $prt.UpdateTime); Attempt=$($prt.Attempt)"
    }
    if ($prt.State -eq 'Expired') {
        Exit-Script 1 "ExpiredPRT | AzureAdPrt=$($prt.Prt); ExpiredHoursAgo=$([math]::Abs($prt.ExpiresInHours)); LastUpdate=$(Format-PrtTime $prt.UpdateTime)"
    }
    if ($prt.State -eq 'Stale') {
        Exit-Script 1 "StalePRT | AzureAdPrt=$($prt.Prt); AgeHours=$($prt.AgeHours); LastUpdate=$(Format-PrtTime $prt.UpdateTime); MaxAgeHours=$MaxPrtAgeHours"
    }
    Exit-Script 0 "Healthy | AzureAdPrt=$($prt.Prt); AgeHours=$($prt.AgeHours); ExpiresInHours=$($prt.ExpiresInHours)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
