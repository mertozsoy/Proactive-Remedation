<#
.SYNOPSIS
  Remediation script that resets stalled remediation scheduling state in IME.

.DESCRIPTION
  Removes LastExecution values that cannot be parsed, sit in the future, or are
  older than the stale limit. Backs up the state with reg export before the change,
  verifies the scan afterwards, then starts the enrollment check-in task. Exits 0
  when the flagged state is gone, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxAgeDays = 30
$FutureToleranceHours = 24
$ScriptIdFilter = @()
$MaxItemsInOutput = 6
$EnableRemediation = $false
$TriggerCheckIn = $true
$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'HealthScriptsSchedule'
$Phase = 'Remediate'
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
function Save-StateBackup { param([string]$KeyPath)
    if (-not (Test-Path -LiteralPath $BackupRoot -ErrorAction Stop)) {
        $null = New-Item -Path $BackupRoot -ItemType Directory -Force -ErrorAction Stop
    }
    $file = Join-Path $BackupRoot ('HealthScripts_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $null = & reg.exe export $KeyPath $file /y 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file -ErrorAction Stop)) { return '' }
    $file
}
function Start-ImeCheckIn {
    $enrollId = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -Name ProviderID -ErrorAction SilentlyContinue).ProviderID -eq 'MS DM Server'
    } | Select-Object -First 1 -ExpandProperty PSChildName
    if (-not $enrollId) { return 'NoEnrollment' }
    $task = Get-ScheduledTask -TaskPath ('\Microsoft\Windows\EnterpriseMgmt\{0}\' -f $enrollId) -TaskName 'PushLaunch' -ErrorAction SilentlyContinue
    if (-not $task) { return 'TaskMissing' }
    try { Start-ScheduledTask -InputObject $task -ErrorAction Stop; return 'Started' } catch { return 'StartFailed' }
}
try {
    if ($MaxAgeDays -lt 1 -or $FutureToleranceHours -lt 0) { throw 'InvalidThreshold' }
    $ScriptsRoot = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts'
    $ExecutionRoot = Join-Path $ScriptsRoot 'Execution'
    $ScriptIdPattern = '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'
    if (-not (Test-Path -LiteralPath $ExecutionRoot -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | HealthScripts=Missing' }

    $flagged = @(Get-ExecutionState -Root $ExecutionRoot | Where-Object { $_.State -ne 'Ok' })
    if ($flagged.Count -eq 0) { Exit-Script 0 'Healthy | Flagged=0' }
    $groups = ($flagged | Group-Object State | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ';'
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Flagged=$($flagged.Count); $groups; Enabled=False" }

    $backup = Save-StateBackup -KeyPath 'HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts'
    if (-not $backup) { Exit-Script 1 "Failed | Flagged=$($flagged.Count); Reason=BackupFailed; Action=NoChange" }

    $cleared = 0
    foreach ($entry in $flagged) {
        try {
            Remove-ItemProperty -LiteralPath $entry.KeyPath -Name 'LastExecution' -ErrorAction Stop
            $cleared++
            Write-IRTLog "Cleared LastExecution for $($entry.ScriptId) state $($entry.State)"
        }
        catch { Write-IRTLog "Skip $($entry.ScriptId) type $($_.Exception.GetType().Name)" 'WARN' }
    }

    $remaining = @(Get-ExecutionState -Root $ExecutionRoot | Where-Object { $_.State -ne 'Ok' })
    if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | Cleared=$cleared; Remaining=$($remaining.Count)" }

    $checkIn = 'Disabled'
    if ($TriggerCheckIn) { $checkIn = Start-ImeCheckIn }
    Exit-Script 0 "Fixed | Cleared=$cleared; $groups; Backup=Created; CheckIn=$checkIn"
}
catch { Exit-Script 1 "Error | Type=$($_.Exception.GetType().Name); Action=InspectHealthScriptsState" }
