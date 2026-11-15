<#
.SYNOPSIS
  Detects repeated Word, Excel and classic Outlook crashes.

.DESCRIPTION
  Counts Application Error event 1000 records for the installed Click-to-Run
  Office directory. Exits 1 when one application reaches the threshold, or
  inspection fails. Exits 0 below the threshold or when not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$LookbackHours = 24
$CrashThreshold = 3
$CooldownHours = 72

$PackageName = 'OfficeQuickRepair'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
$StateFile = Join-Path (Split-Path $LogFile) "IRT_$PackageName.state.json"
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
function Get-RepairState {
    $state = [pscustomobject]@{ LastAttemptUtc = $null; LastReturnedUtc = $null }
    if (Test-Path -LiteralPath $StateFile) {
        $saved = Get-Content -LiteralPath $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($saved.Schema -ne 1 -or -not $saved.LastAttemptUtc) { throw 'InvalidState' }
        foreach ($name in @('LastAttemptUtc', 'LastReturnedUtc')) {
            if ($saved.$name) {
                $value = [datetimeoffset]::Parse($saved.$name, [cultureinfo]::InvariantCulture).UtcDateTime
                if ($value -gt [datetime]::UtcNow.AddMinutes(5)) { throw 'FutureState' }
                $state.$name = $value
            }
        }
        if ($state.LastReturnedUtc -and $state.LastReturnedUtc -lt $state.LastAttemptUtc) { throw 'InvalidStateOrder' }
    }
    return $state
}
function Get-OfficeCrashSummary { param([string]$OfficeRoot, [datetime]$StartTime)
    $counts = @{ 'winword.exe' = 0; 'excel.exe' = 0; 'outlook.exe' = 0 }
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $StartTime.ToLocalTime() } -ErrorAction Stop)
    }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
        $events = @()
    }
    foreach ($crashEvent in $events) {
        $xml = [xml]$crashEvent.ToXml()
        $fields = @{}
        foreach ($node in $xml.Event.EventData.Data) { $fields[[string]$node.Name] = [string]$node.InnerText }
        if (-not $fields.ContainsKey('AppName') -or -not $fields.ContainsKey('AppPath')) { throw 'UnsupportedEventSchema' }
        $app = $fields['AppName'].ToLowerInvariant()
        if ($counts.ContainsKey($app) -and $fields['AppPath'].StartsWith($OfficeRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $counts[$app]++
        }
    }
    $affected = @($counts.Keys | Where-Object { $counts[$_] -ge $CrashThreshold } | Sort-Object)
    $text = (@($counts.Keys | Sort-Object | ForEach-Object { '{0}={1}' -f $_, $counts[$_] }) -join '; ')
    $total = ($counts.Values | Measure-Object -Sum).Sum
    return [pscustomobject]@{ Affected = $affected; Text = $text; Total = $total }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ($LookbackHours -lt 1 -or $CrashThreshold -lt 2 -or $CooldownHours -lt $LookbackHours) { throw 'InvalidSettings' }
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (-not (Test-Path -LiteralPath $configPath)) { Exit-Script 0 'NotApplicable | Reason=NoClickToRun' }
    $config = Get-ItemProperty -LiteralPath $configPath
    if ([string]$config.Platform -notin @('x86', 'x64')) { Exit-Script 0 'NotApplicable | Reason=UnsupportedOfficePlatform' }
    if (-not $config.InstallationPath -or -not [IO.Path]::IsPathRooted($config.InstallationPath)) { throw 'InvalidOfficePath' }
    $officeRoot = [IO.Path]::GetFullPath($config.InstallationPath).TrimEnd('\') + '\'
    $state = Get-RepairState
    $start = [datetime]::UtcNow.AddHours(-$LookbackHours)
    if ($state.LastReturnedUtc -and $state.LastReturnedUtc -gt $start) { $start = $state.LastReturnedUtc }
    $crashes = Get-OfficeCrashSummary -OfficeRoot $officeRoot -StartTime $start
    if ($crashes.Affected.Count -gt 0) {
        if ($state.LastAttemptUtc -and [datetime]::UtcNow -lt $state.LastAttemptUtc.AddHours($CooldownHours)) {
            Exit-Script 1 "Pending | Reason=RepairCooldown; $($crashes.Text); Action=InvestigateRecurrence"
        }
        Exit-Script 1 "Drift | Threshold=$CrashThreshold; WindowHours=$LookbackHours; $($crashes.Text)"
    }
    if ($state.LastAttemptUtc -and -not $state.LastReturnedUtc) {
        Exit-Script 1 "Pending | Reason=PreviousAttemptUnverified; $($crashes.Text); Action=ReviewRepair"
    }
    if ($state.LastReturnedUtc -and [datetime]::UtcNow -lt $state.LastReturnedUtc.AddHours($LookbackHours)) {
        Exit-Script 0 "Observing | Reason=RepairClientReturned; $($crashes.Text); Stability=NotProven"
    }
    Exit-Script 0 "Healthy | Threshold=$CrashThreshold; WindowHours=$LookbackHours; $($crashes.Text)"
}
catch { Exit-Script 1 "Failed | Reason=InspectionError; ErrorType=$($_.Exception.GetType().Name)" }
