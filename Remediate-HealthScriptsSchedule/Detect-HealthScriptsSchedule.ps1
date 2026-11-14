<#
.SYNOPSIS
  Detection script for stalled remediation scheduling state in IME.

.DESCRIPTION
  Reads LastExecution values from the IME remediation state and flags entries that
  cannot be parsed, sit in the future, or are older than the stale limit. Exits 1
  if at least one entry is flagged, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxAgeDays = 30
$FutureToleranceHours = 24
$ScriptIdFilter = @()
$MaxItemsInOutput = 6

$PackageName = 'HealthScriptsSchedule'
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
function ConvertTo-ExecutionTime { param([string]$Value)
    $parsed = [datetime]::MinValue
    $cultures = @([Globalization.CultureInfo]::CurrentCulture, [Globalization.CultureInfo]::InvariantCulture)
    foreach ($culture in $cultures) {
        if ([datetime]::TryParse($Value, $culture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) { return $parsed }
    }
    $formats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss', 'M/d/yyyy H:mm:ss', 'd.M.yyyy HH:mm:ss')
    foreach ($format in $formats) {
        if ([datetime]::TryParseExact($Value, $format, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) { return $parsed }
    }
    return $null
}
function Get-ExecutionState { param([string]$Root)
    $entries = @()
    if (-not (Test-Path -LiteralPath $Root -ErrorAction Stop)) { return $entries }
    $now = Get-Date
    foreach ($key in Get-ChildItem -LiteralPath $Root -Recurse -ErrorAction Stop) {
        $raw = $key.GetValue('LastExecution')
        if ($null -eq $raw) { continue }
        $text = ([string]$raw).Trim()
        $segments = $key.Name -split '\\'
        $scriptId = ''
        for ($i = $segments.Count - 1; $i -ge 0; $i--) {
            if ($segments[$i] -match $ScriptIdPattern) { $scriptId = $segments[$i]; break }
        }
        if ($ScriptIdFilter.Count -gt 0 -and $ScriptIdFilter -notcontains $scriptId) { continue }
        $stamp = ConvertTo-ExecutionTime -Value $text
        if ($null -eq $stamp) { $state = 'Unparseable' }
        elseif ($stamp -gt $now.AddHours($FutureToleranceHours)) { $state = 'Future' }
        elseif ($stamp -lt $now.AddDays(-$MaxAgeDays)) { $state = 'Stale' }
        else { $state = 'Ok' }
        $entries += [pscustomobject]@{ KeyPath = $key.PSPath; ScriptId = $scriptId; Stamp = $stamp; State = $state }
    }
    $entries
}
try {
    if ($MaxAgeDays -lt 1 -or $FutureToleranceHours -lt 0) { throw 'InvalidThreshold' }
    $ScriptsRoot = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts'
    $ExecutionRoot = Join-Path $ScriptsRoot 'Execution'
    $ScriptIdPattern = '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'
    if (-not (Test-Path -LiteralPath $ExecutionRoot -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | HealthScripts=Missing' }

    $entries = @(Get-ExecutionState -Root $ExecutionRoot)
    if ($entries.Count -eq 0) { Exit-Script 0 'Healthy | Scripts=0' }

    $flagged = @($entries | Where-Object { $_.State -ne 'Ok' })
    if ($flagged.Count -eq 0) { Exit-Script 0 "Healthy | Scripts=$($entries.Count); Flagged=0" }

    $groups = ($flagged | Group-Object State | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ';'
    $items = ($flagged | Select-Object -First $MaxItemsInOutput | ForEach-Object { '{0}({1})' -f $_.ScriptId, $_.State }) -join ','
    $suffix = ''
    if ($flagged.Count -gt $MaxItemsInOutput) { $suffix = ',+' + ($flagged.Count - $MaxItemsInOutput) }
    Exit-Script 1 "Drift | Scripts=$($entries.Count); $groups; Items=$items$suffix"
}
catch { Exit-Script 1 "Error | Type=$($_.Exception.GetType().Name); Action=InspectHealthScriptsState" }
