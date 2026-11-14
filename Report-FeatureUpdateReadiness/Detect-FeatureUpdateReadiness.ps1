<#
.SYNOPSIS
  Detection script for feature update readiness.

.DESCRIPTION
  Reports safeguard holds, compatibility blockers and end of servicing dates. Exits 1 if appraiser data is out of date.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$script:Phase = 'Detect'

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

$script:RemId    = 'REM-004'
$script:LogDir   = if ($env:ProgramData) { Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs' } else { $null }
$script:StateKey = 'HKLM:\SOFTWARE\IntuneRemediations\REM-004'

$ReportAttentionAsIssue = $false
$WarnDaysBeforeEndOfServicing = 90
$AppraiserMaxAgeDays   = 7
$RefreshThrottleDays   = 7

$ServicingTable = @{
    '19045' = @{ Name = 'Win10 22H2'; Pro = '2025-10-14'; Ent = '2025-10-14' }
    '22621' = @{ Name = 'Win11 22H2'; Pro = '2024-10-08'; Ent = '2025-10-14' }
    '22631' = @{ Name = 'Win11 23H2'; Pro = '2025-11-11'; Ent = '2026-11-10' }
    '26100' = @{ Name = 'Win11 24H2'; Pro = '2026-10-13'; Ent = '2027-10-12' }
    '26200' = @{ Name = 'Win11 25H2'; Pro = '2027-10-12'; Ent = '2028-10-10' }
    '26300' = @{ Name = 'Win11 26H2'; Pro = '2028-10-10'; Ent = '2029-10-09' }
    '28000' = @{ Name = 'Win11 26H1'; Pro = '2028-03-14'; Ent = '2029-03-13' }
}
$AppraiserTaskPath = '\Microsoft\Windows\Application Experience\'
$AppraiserTaskName = 'Microsoft Compatibility Appraiser'

function Get-RemRegValue {
    param([string]$Path, [string]$Name)
    $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.$Name }
    return $null
}
function Get-RemSubKeyNames {
    param([string]$Path)
    @(Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object PSChildName)
}
function Get-RemOsInfo {
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{ Build = [string]$cv.CurrentBuild; DisplayVersion = [string]$cv.DisplayVersion; EditionId = [string]$cv.EditionID; Ubr = $cv.UBR }
}
function Get-RemAppraiserLastRun {
    $t = Get-ScheduledTask -TaskPath $AppraiserTaskPath -TaskName $AppraiserTaskName -ErrorAction SilentlyContinue
    if (-not $t) { $t = Get-ScheduledTask -TaskPath $AppraiserTaskPath -TaskName ($AppraiserTaskName + '*') -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $t) { return [pscustomobject]@{ Exists = $false; State = $null; LastRun = $null } }
    $i = Get-ScheduledTaskInfo -InputObject $t -ErrorAction SilentlyContinue
    $last = if ($i -and $i.LastRunTime -and $i.LastRunTime.Year -gt 2000) { $i.LastRunTime } else { $null }
    [pscustomobject]@{ Exists = $true; State = [string]$t.State; LastRun = $last }
}
function Get-RemTpmMajor {
    try {
        $t = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($t -and $t.SpecVersion) { return [int](($t.SpecVersion -split ',')[0] -split '\.')[0] }
    } catch { }
    return 0
}
function Get-RemSecureBoot { try { [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $false } }
function ConvertTo-RemDate {
    param([string]$Text)
    $t = [datetime]::MinValue
    if ($Text -and [datetime]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) { return $t }
    return $null
}

function Get-ReadinessFindings {
    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($Kind, $Code) $findings.Add([pscustomobject]@{ Kind = $Kind; Code = $Code }) }
    $now = Get-Date

    $os = Get-RemOsInfo
    $family = if ($os.EditionId -match '^(Enterprise|Education|IoTEnterprise|ServerRdsh)') { 'Ent' } else { 'Pro' }
    if ($os.EditionId -match 'LTSC|EnterpriseS') { $family = 'LTSC' }
    & $add 'Info' ('OS={0} {1}.{2} {3}' -f $os.DisplayVersion, $os.Build, $os.Ubr, $os.EditionId)

    if ($family -eq 'LTSC') { & $add 'Info' 'Servicing=LTSC(out of scope)' }
    elseif ($ServicingTable.ContainsKey($os.Build)) {
        $eos = [datetime]::ParseExact($ServicingTable[$os.Build][$family], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ($now -ge $eos) { & $add 'Attention' ('Servicing=Ended({0:yyyy-MM-dd})' -f $eos) }
        elseif (($eos - $now).TotalDays -le $WarnDaysBeforeEndOfServicing) { & $add 'Attention' ('Servicing=EndsSoon({0:yyyy-MM-dd})' -f $eos) }
        else { & $add 'Info' ('Servicing=Supported(until {0:yyyy-MM-dd})' -f $eos) }
    }
    else { & $add 'Info' ('Servicing=UnknownBuild({0})' -f $os.Build) }

    $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags'
    $gstatus = Get-RemRegValue "$base\Appraiser\GWX" 'GStatus'
    $holdIds = @()
    foreach ($target in (Get-RemSubKeyNames "$base\TargetVersionUpgradeExperienceIndicators")) {
        $k = "$base\TargetVersionUpgradeExperienceIndicators\$target"
        $id = Get-RemRegValue $k 'GatedBlockId'
        if ($id -and $id -ne 'None') { $holdIds += ('{0}:{1}' -f $target, $id) }
        $upg = Get-RemRegValue $k 'UpgEx'
        if ($upg -eq 'Red') {
            $reason = Get-RemRegValue $k 'RedReason'
            & $add 'Attention' ('AppraiserRed({0}:{1})' -f $target, ($(if ($reason) { $reason } else { 'unknown' })))
        }
    }
    if ($gstatus -eq 0 -or $holdIds.Count) { & $add 'Attention' ('SafeguardHold({0})' -f ($(if ($holdIds) { $holdIds -join ',' } else { 'id unknown' }))) }

    if ((Get-RemTpmMajor) -lt 2) { & $add 'Attention' 'TPM2=Missing' }
    if (-not (Get-RemSecureBoot)) { & $add 'Attention' 'SecureBoot=Off' }

    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if ((Get-RemRegValue $wu 'TargetReleaseVersion') -eq 1) {
        & $add 'Attention' ('PolicyPinned(GPO:{0} {1})' -f (Get-RemRegValue $wu 'ProductVersion'), (Get-RemRegValue $wu 'TargetReleaseVersionInfo'))
    }
    $mdmTrv = Get-RemRegValue 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update' 'TargetReleaseVersion'
    if ($mdmTrv) { & $add 'Info' ('MdmTargetReleaseVersion={0}' -f $mdmTrv) }

    $app = Get-RemAppraiserLastRun
    if (-not $app.Exists) { & $add 'Attention' 'AppraiserTask=Missing' }
    elseif ($app.State -eq 'Disabled') { & $add 'Attention' 'AppraiserTask=Disabled(see REM-001)' }
    elseif (-not $app.LastRun -or ($now - $app.LastRun).TotalDays -gt $AppraiserMaxAgeDays) {
        $lastRefresh = ConvertTo-RemDate (Get-RemRegValue $script:StateKey 'LastRefresh')
        if ($lastRefresh -and ($now - $lastRefresh).TotalDays -lt $RefreshThrottleDays) { & $add 'Info' 'Appraiser=Stale(refresh throttled)' }
        else { & $add 'Fixable' 'Appraiser=Stale' }
    }
    return $findings
}

function Format-Findings {
    param($Findings)
    $fix = @($Findings | Where-Object Kind -eq 'Fixable'   | ForEach-Object Code)
    $att = @($Findings | Where-Object Kind -eq 'Attention' | ForEach-Object Code)
    $inf = @($Findings | Where-Object Kind -eq 'Info'      | ForEach-Object Code)
    $parts = @($(if ($fix.Count) { 'FIXABLE' } elseif ($att.Count) { 'ATTENTION' } else { 'OK' }))
    if ($fix.Count) { $parts += 'Fixable: ' + ($fix -join ', ') }
    if ($att.Count) { $parts += 'Attention: ' + ($att -join ', ') }
    if ($inf.Count) { $parts += 'Info: ' + ($inf -join ', ') }
    $parts -join ' | '
}

function Invoke-RemDetection {
    $f = Get-ReadinessFindings
    $fix = @($f | Where-Object Kind -eq 'Fixable').Count
    $att = @($f | Where-Object Kind -eq 'Attention').Count
    $code = if ($fix -gt 0 -or ($ReportAttentionAsIssue -and $att -gt 0)) { 1 } else { 0 }
    [pscustomobject]@{ ExitCode = $code; Output = (Format-Findings $f) }
}

if ($MyInvocation.InvocationName -ne '.') { Complete-Rem { Invoke-RemDetection } }
