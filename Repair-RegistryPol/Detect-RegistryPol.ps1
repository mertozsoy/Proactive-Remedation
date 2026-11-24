<#
.SYNOPSIS
  Detection script for a corrupt local Registry.pol file.

.DESCRIPTION
  Reads %SystemRoot%\System32\GroupPolicy\Machine\Registry.pol and checks the container structure: PReg signature, version, first record start and last record end. Also counts Group Policy event 1096 from the last $EventWindowDays days. Exits 1 if the file is corrupt, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyFile      = Join-Path $env:SystemRoot 'System32\GroupPolicy\Machine\Registry.pol'
$EventWindowDays = 7
$PolicyEventLog  = 'Microsoft-Windows-GroupPolicy/Operational'
$PolicyEventId   = 1096

$PackageName = 'RegistryPol'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-PolicyFileState { param([string]$Path)
    $state = [pscustomobject]@{ Exists = $false; Valid = $false; Reason = 'Missing'; Bytes = 0 }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $state }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $state.Exists = $true
    $state.Bytes = $bytes.Length
    if ($bytes.Length -eq 0) { $state.Reason = 'EmptyFile'; return $state }
    if ($bytes.Length -lt 8) { $state.Reason = 'TooShort'; return $state }
    if (-not ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x52 -and $bytes[2] -eq 0x65 -and $bytes[3] -eq 0x67)) {
        $state.Reason = 'BadSignature'
        return $state
    }
    $version = [System.BitConverter]::ToUInt32($bytes, 4)
    if ($version -ne 1) { $state.Reason = "BadVersion=$version"; return $state }
    if (($bytes.Length % 2) -ne 0) { $state.Reason = 'OddLength'; return $state }
    if ($bytes.Length -gt 8) {
        if (-not ($bytes[8] -eq 0x5B -and $bytes[9] -eq 0x00)) { $state.Reason = 'BadRecordStart'; return $state }
        $last = $bytes.Length - 1
        if (-not ($bytes[$last] -eq 0x00 -and $bytes[$last - 1] -eq 0x5D)) { $state.Reason = 'TruncatedRecord'; return $state }
    }
    $state.Valid = $true
    $state.Reason = 'OK'
    $state
}

function Get-PolicyErrorCount { param([datetime]$Since)
    try {
        $filter = @{ LogName = $PolicyEventLog; Id = $PolicyEventId; StartTime = $Since }
        $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        return $events.Count
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return 0 }
        return -1
    }
}

try {
    $state = Get-PolicyFileState -Path $PolicyFile
    Write-IRTLog ("Policy file state: Exists={0} Valid={1} Reason={2} Bytes={3}" -f $state.Exists, $state.Valid, $state.Reason, $state.Bytes)

    if (-not $state.Exists) { Exit-Script 0 "NotApplicable | RegistryPol=missing; Path=$PolicyFile" }
    if ($state.Valid) {
        $events = Get-PolicyErrorCount -Since (Get-Date).AddDays(-$EventWindowDays)
        Exit-Script 0 "Healthy | RegistryPol=valid; Bytes=$($state.Bytes); Policy1096=$events"
    }

    $errors = Get-PolicyErrorCount -Since (Get-Date).AddDays(-$EventWindowDays)
    $stamp = (Get-Item -LiteralPath $PolicyFile).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
    Exit-Script 1 "Drift | RegistryPol=corrupt; Reason=$($state.Reason); Bytes=$($state.Bytes); Modified=$stamp; Policy1096=$errors"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
