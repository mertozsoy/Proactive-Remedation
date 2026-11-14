<#
.SYNOPSIS
  Remediation script for the Windows servicing and diagnostic pipeline.

.DESCRIPTION
  Sets the broken components back to their Windows defaults. Policy controlled settings are not changed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$script:Phase = 'Remediate'

$ErrorActionPreference = 'Stop'

if ($MyInvocation.InvocationName -ne '.' -and $env:PROCESSOR_ARCHITEW6432 -in @('AMD64', 'ARM64')) {
    $ps64 = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps64) {
        & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
}

function Write-RemLog {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    try {
        $dir = $script:LogDir
        if (-not $dir) { return }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $file = Join-Path $dir ('IRT-{0}.log' -f $script:RemId)
        if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1MB)) {
            Move-Item -LiteralPath $file -Destination ($file + '.old') -Force
        }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $script:Phase, $Level, $Message
        Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    }
    catch { }
}

function Format-RemOutput {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -gt 2000) { return $Text.Substring(0, 1997) + '...' }
    return $Text
}

function Complete-Rem {
    param([scriptblock]$Main)
    try { $r = & $Main }
    catch { $r = [pscustomobject]@{ ExitCode = 2; Output = 'ERROR | ' + $_.Exception.Message } }
    if ($null -eq $r -or $null -eq $r.ExitCode) { $r = [pscustomobject]@{ ExitCode = 2; Output = 'ERROR | script returned no result' } }
    $out = Format-RemOutput $r.Output
    Write-RemLog ('EXIT {0} | {1}' -f $r.ExitCode, $out)
    Write-Output $out
    exit $r.ExitCode
}

$script:RemId    = 'REM-001'
$script:LogDir   = if ($env:ProgramData) { Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs' } else { $null }
$script:StateKey = 'HKLM:\SOFTWARE\IntuneRemediations\REM-001'

$ReportAttentionAsIssue = $false

$MaxFixesPer30Days = 3

$ReportDriftAsIssue = $true

$ServiceRules = @(
    [pscustomobject]@{ Name = 'DiagTrack'; DefaultStart = 'Automatic'; MustRun = $true }
    [pscustomobject]@{ Name = 'wlidsvc';   DefaultStart = 'Manual';    MustRun = $false }
)
$TaskRules = @(
    [pscustomobject]@{ Label = 'Appraiser';        Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser*' }
    [pscustomobject]@{ Label = 'Census';           Path = '\Microsoft\Windows\Device Information\';     Name = 'Device' }

    [pscustomobject]@{ Label = 'SecureBootUpdate'; Path = '\Microsoft\Windows\PI\';                     Name = 'Secure-Boot-Update'; ReportOnly = $true }
    [pscustomobject]@{ Label = 'USOScan';          Path = '\Microsoft\Windows\UpdateOrchestrator\';     Name = 'Schedule Scan' }
)

function Get-RemService {
    param([string]$Name)
    $s = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction SilentlyContinue
    if (-not $s) { return [pscustomobject]@{ Exists = $false; StartMode = $null; State = $null } }
    [pscustomobject]@{ Exists = $true; StartMode = [string]$s.StartMode; State = [string]$s.State }
}
function Get-RemTasks {
    param([string]$Path, [string]$Name)
    @(Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction SilentlyContinue |
        ForEach-Object { [pscustomobject]@{ TaskPath = $_.TaskPath; TaskName = $_.TaskName; State = [string]$_.State } })
}
function Get-RemRegValue {
    param([string]$Path, [string]$Name)
    $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.$Name }
    return $null
}
function Get-RemFixLog {
    $raw = Get-RemRegValue -Path $script:StateKey -Name 'FixLog'
    $list = @()
    if ($raw) {
        foreach ($e in ($raw -split ';')) {
            $parts = $e -split '=', 2
            if ($parts.Count -eq 2) {
                $t = [datetime]::MinValue
                if ([datetime]::TryParse($parts[1], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) {
                    $list += [pscustomobject]@{ Code = $parts[0]; Time = $t }
                }
            }
        }
    }
    @($list | Where-Object { $_.Time -gt (Get-Date).AddDays(-30) })
}

function Get-PipelineFindings {
    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($Kind, $Code, $Target) $findings.Add([pscustomobject]@{ Kind = $Kind; Code = $Code; Target = $Target }) }

    foreach ($rule in $ServiceRules) {
        $s = Get-RemService -Name $rule.Name
        $wantMode = if ($rule.DefaultStart -eq 'Automatic') { 'Auto' } else { $rule.DefaultStart }
        if (-not $s.Exists)                                      { & $add 'Attention' ("Svc:{0}=Missing" -f $rule.Name) $rule }
        elseif ($s.StartMode -eq 'Disabled')                     { & $add 'Fixable'   ("Svc:{0}=Disabled" -f $rule.Name) $rule }
        elseif ($rule.MustRun -and $s.StartMode -ne $wantMode)   { & $add 'Fixable'   ("Svc:{0}=Start{1}" -f $rule.Name, $s.StartMode) $rule }
        elseif ($rule.MustRun -and $s.State -ne 'Running')       { & $add 'Fixable'   ("Svc:{0}={1}" -f $rule.Name, $s.State) $rule }
    }

    foreach ($rule in $TaskRules) {
        $tasks = @(Get-RemTasks -Path $rule.Path -Name $rule.Name)
        if ($tasks.Count -eq 0) { & $add 'Attention' ("Task:{0}=Missing" -f $rule.Label) $rule; continue }
        foreach ($t in ($tasks | Where-Object { $_.State -eq 'Disabled' })) {
            $kind = if ($rule.PSObject.Properties['ReportOnly'] -and $rule.ReportOnly) { 'Attention' } else { 'Fixable' }
            & $add $kind ("Task:{0}=Disabled" -f $rule.Label) $t
        }
    }

    $gpo = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    $mdm = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\System'
    $tel = @((Get-RemRegValue $gpo 'AllowTelemetry'), (Get-RemRegValue $mdm 'AllowTelemetry')) | Where-Object { $null -ne $_ }
    if ($tel | Where-Object { [int]$_ -eq 0 }) {
        & $add 'Attention' 'Policy:AllowTelemetry=0' $null

        foreach ($f in @($findings | Where-Object { $_.Kind -eq 'Fixable' -and $_.Code -like 'Svc:DiagTrack*' })) { $f.Kind = 'Attention'; $f.Code += '(PolicyTelemetryOff)' }
    }
    if ((Get-RemRegValue $gpo 'DisableOneSettingsDownloads') -eq 1) { & $add 'Attention' 'Policy:DisableOneSettingsDownloads=1' $null }
    $devName = @((Get-RemRegValue $gpo 'AllowDeviceNameInDiagnosticData'), (Get-RemRegValue $mdm 'AllowDeviceNameInDiagnosticData')) | Where-Object { $null -ne $_ }
    if (-not ($devName | Where-Object { [int]$_ -eq 1 })) { & $add 'Info' 'DeviceNameInDiagData=NotAllowed' $null }

    $log = Get-RemFixLog
    foreach ($f in @($findings | Where-Object Kind -eq 'Fixable')) {
        $count = @($log | Where-Object { $_.Code -eq $f.Code -or $_.Code -eq ('FAIL:' + $f.Code) }).Count
        if ($count -ge $MaxFixesPer30Days) {
            $f.Kind = 'Drift'
            $f.Code = $f.Code + '(ExternalDrift x' + $count + ')'
        }
    }
    return $findings
}

function Format-Findings {
    param($Findings)
    $fix = @($Findings | Where-Object Kind -eq 'Fixable'   | ForEach-Object Code)
    $att = @($Findings | Where-Object { $_.Kind -in 'Attention', 'Drift' } | ForEach-Object Code)
    $inf = @($Findings | Where-Object Kind -eq 'Info'      | ForEach-Object Code)
    $status = if ($fix.Count) { 'FIXABLE' } elseif (@($Findings | Where-Object Kind -eq 'Drift').Count) { 'DRIFT' } elseif ($att.Count) { 'ATTENTION' } else { 'OK' }
    $parts = @($status)
    if ($fix.Count) { $parts += 'Fixable: ' + ($fix -join ', ') }
    if ($att.Count) { $parts += 'Attention: ' + ($att -join ', ') }
    if ($inf.Count) { $parts += 'Info: ' + ($inf -join ', ') }
    return ($parts -join ' | ')
}

$DryRun = $false

function Set-RemServiceStart { param([string]$Name, [string]$StartupType) Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop }
function Start-RemService    { param([string]$Name) Start-Service -Name $Name -ErrorAction Stop }
function Enable-RemTask      { param([string]$Path, [string]$Name) Enable-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction Stop | Out-Null }
function Add-RemFixLog {
    param([string]$Code)
    $entries = @(Get-RemFixLog | ForEach-Object { '{0}={1}' -f $_.Code, $_.Time.ToString('s') })
    $entries += '{0}={1}' -f $Code, (Get-Date).ToString('s')
    if (-not (Test-Path -LiteralPath $script:StateKey)) { New-Item -Path $script:StateKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $script:StateKey -Name 'FixLog' -Value ($entries -join ';') -Type String
}

function Invoke-RemRemediation {
    $before = Get-PipelineFindings
    $todo = @($before | Where-Object Kind -eq 'Fixable')
    if ($todo.Count -eq 0) {
        $code = if (@($before | Where-Object { $_.Kind -in 'Attention', 'Drift' }).Count) { 2 } else { 0 }
        return [pscustomobject]@{ ExitCode = $code; Output = 'NOTHING-TO-FIX | ' + (Format-Findings $before) }
    }

    $done = @(); $failed = @()
    foreach ($f in $todo) {
        try {
            if ($DryRun) { Write-RemLog ('WHATIF fix ' + $f.Code); $done += ('WhatIf:' + $f.Code); continue }
            if ($f.Code -like 'Svc:*') {
                $rule = $f.Target
                if ($f.Code -match '=Disabled$|=Start') { Set-RemServiceStart -Name $rule.Name -StartupType $rule.DefaultStart }
                if ($rule.MustRun) { Start-RemService -Name $rule.Name }
            }
            elseif ($f.Code -like 'Task:*') {
                Enable-RemTask -Path $f.Target.TaskPath -Name $f.Target.TaskName
            }
            Add-RemFixLog -Code $f.Code
            Write-RemLog ('Fixed ' + $f.Code)
            $done += $f.Code
        }
        catch {
            Write-RemLog ('Failed ' + $f.Code + ': ' + $_.Exception.Message) 'ERROR'
            try { Add-RemFixLog -Code ('FAIL:' + $f.Code) } catch { }
            $failed += $f.Code
        }
    }

    if ($DryRun) { return [pscustomobject]@{ ExitCode = 0; Output = 'DRYRUN | ' + ($done -join ', ') } }

    $after = Get-PipelineFindings
    $stillFix = @($after | Where-Object Kind -eq 'Fixable')
    $summary = 'Fixed: ' + ($(if ($done) { $done -join ', ' } else { 'none' })) + ' | After: ' + (Format-Findings $after)
    if ($failed.Count -or $stillFix.Count) { return [pscustomobject]@{ ExitCode = 1; Output = 'FAILED | ' + $summary } }
    return [pscustomobject]@{ ExitCode = 0; Output = 'REMEDIATED | ' + $summary }
}

if ($MyInvocation.InvocationName -ne '.') { Complete-Rem { Invoke-RemRemediation } }
