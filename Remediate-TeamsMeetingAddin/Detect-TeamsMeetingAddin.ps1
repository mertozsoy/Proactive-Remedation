<#
.SYNOPSIS
  Detection script for the Teams Meeting add-in in classic Outlook.

.DESCRIPTION
  Checks registration and LoadBehavior of the add-in for the signed in user. Exits 1 if it is missing or disabled.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
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

$script:RemId    = 'REM-002'
$script:LogDir   = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs' } else { $null }
$script:StateKey = 'HKCU:\Software\IntuneRemediations\REM-002'

$ReportAttentionAsIssue   = $false
$MaxFixesPer30Days        = 3

$AllowWhileOutlookRunning = $false

$AddinProgId  = 'TeamsAddin.FastConnect'
$AddinDllName = 'Microsoft.Teams.AddinLoader.dll'

function Get-RemRegValue {
    param([string]$Path, [string]$Name)
    $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.$Name }
    return $null
}
function Test-RemRegKey { param([string]$Path) Test-Path -LiteralPath $Path }
function Test-RemFile   { param([string]$Path) Test-Path -LiteralPath $Path -PathType Leaf }
function Test-RemMicrosoftSigned {

    param([string]$Path)
    $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction SilentlyContinue
    return [bool]($sig -and $sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'O=Microsoft Corporation')
}
function Get-RemOfficeBitness {
    $p = Get-RemRegValue 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' 'Platform'
    if (-not $p) { $p = Get-RemRegValue 'HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook' 'Bitness' }
    if ($p -match '86') { return 'x86' }
    if ($p -match '64') { return 'x64' }
    return $null
}
function Test-RemClassicOutlook {
    $path = Get-RemRegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE' '(default)'
    return [bool]($path -and (Test-Path -LiteralPath $path))
}
function Get-RemAddinInstalls {

    $roots = @()
    if ($env:LOCALAPPDATA) { $roots += Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddin' }
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) { if ($pf) { $roots += Join-Path $pf 'Microsoft\TeamsMeetingAddin' } }
    $list = @()
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($d in (Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue)) {
            $v = $null
            if ([version]::TryParse($d.Name, [ref]$v)) { $list += [pscustomobject]@{ Version = $v; Path = $d.FullName } }
        }
    }
    @($list | Sort-Object Version -Descending)
}
function Get-RemResiliencyHits {

    $key = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems'
    $hits = @()
    if (-not (Test-Path -LiteralPath $key)) { return $hits }
    $item = Get-Item -LiteralPath $key
    foreach ($name in $item.GetValueNames()) {
        $data = $item.GetValue($name)
        if ($data -is [byte[]]) {
            $text = [Text.Encoding]::Unicode.GetString($data)
            if ($text -match 'Microsoft\.Teams\.AddinLoader|TeamsAddin') { $hits += $name }
        }
    }
    $hits
}
function Test-RemOutlookRunning { [bool](Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId }) }
function Get-RemFixLog {
    $raw = Get-RemRegValue -Path $script:StateKey -Name 'FixLog'
    $list = @()
    if ($raw) {
        foreach ($e in ($raw -split ';')) {
            $parts = $e -split '=', 2
            $t = [datetime]::MinValue
            if ($parts.Count -eq 2 -and [datetime]::TryParse($parts[1], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) {
                $list += [pscustomobject]@{ Code = $parts[0]; Time = $t }
            }
        }
    }
    @($list | Where-Object { $_.Time -gt (Get-Date).AddDays(-30) })
}

function Get-AddinFindings {
    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($Kind, $Code, $Data) $findings.Add([pscustomobject]@{ Kind = $Kind; Code = $Code; Data = $Data }) }

    if (-not (Test-RemClassicOutlook)) { & $add 'NotApplicable' 'ClassicOutlook=NotInstalled' $null; return $findings }
    $bit = Get-RemOfficeBitness
    if (-not $bit) { & $add 'Attention' 'OfficeBitness=Unknown' $null; return $findings }

    $installs = @(Get-RemAddinInstalls)
    $usable = $installs | Where-Object { Test-RemFile ([IO.Path]::Combine($_.Path, $bit, $AddinDllName)) } | Select-Object -First 1
    if (-not $usable) { & $add 'Attention' 'Addin=NotInstalled(start new Teams to provision it)' $null }
    if ($installs | Where-Object { $_.Version.Major -eq 1 -and $_.Version.Minor -eq 23 }) { & $add 'Attention' 'Addin=Legacy1.23(run Microsoft UninstallOldTMA)' $null }

    $policyBlocked = $false
    foreach ($root in 'HKCU:\Software\Policies\Microsoft\Cloud\Office\16.0\Outlook\Resiliency', 'HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Resiliency') {
        $polList = Get-RemRegValue "$root\AddinList" $AddinProgId
        if ([string]$polList -eq '0') { $policyBlocked = $true }

        if ((Get-RemRegValue $root 'RestrictToList') -eq 1 -and [string]$polList -notin @('1', '2')) { $policyBlocked = $true }
        if ($policyBlocked) { & $add 'Attention' 'Policy:AddinBlocked(AddinList/RestrictToList)' $null; break }
    }
    foreach ($sec in 'HKCU:\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Security', 'HKCU:\SOFTWARE\Policies\Microsoft\Cloud\Office\16.0\Outlook\Security') {
        if ((Get-RemRegValue $sec 'promptoomaddressinformationaccess') -eq 0) { & $add 'Attention' 'Policy:OOMAddressAccess=AutoDeny' $null }
        if ((Test-RemRegKey "$sec\TrustedAddins") -and $null -eq (Get-RemRegValue "$sec\TrustedAddins" $AddinDllName)) {
            & $add 'Attention' 'Policy:TrustedAddins=LoaderNotListed' $null
        }
    }

    $hkcuKey = "HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins\$AddinProgId"
    $hklmKeys = @("HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\$AddinProgId", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\$AddinProgId")
    $hklmKey = $hklmKeys | Where-Object { Test-RemRegKey $_ } | Select-Object -First 1
    if (Test-RemRegKey $hkcuKey) {
        $lb = Get-RemRegValue $hkcuKey 'LoadBehavior'
        if ($lb -ne 3 -and -not $policyBlocked) { & $add 'Fixable' ("LoadBehavior={0}" -f $lb) $hkcuKey }
    }
    elseif ($hklmKey) {
        $lb = Get-RemRegValue $hklmKey 'LoadBehavior'
        if ($lb -ne 3) { & $add 'Attention' ("MachineLoadBehavior={0}" -f $lb) $hklmKey }
    }
    elseif ($usable) { & $add 'Fixable' 'Registration=Missing' $usable }

    $hits = @(Get-RemResiliencyHits)
    if ($hits.Count -and -not $policyBlocked) { & $add 'Fixable' 'Resiliency=HardDisabled' $hits }

    $log = Get-RemFixLog
    foreach ($f in @($findings | Where-Object Kind -eq 'Fixable')) {
        $n = @($log | Where-Object Code -eq $f.Code).Count
        if ($n -ge $MaxFixesPer30Days) { $f.Kind = 'Attention'; $f.Code += "(ExternalDrift x$n)" }
    }
    if ($usable) { & $add 'Info' ("Version={0} {1}" -f $usable.Version, $bit) $null }
    return $findings
}

function Format-Findings {
    param($Findings)
    if ($Findings | Where-Object Kind -eq 'NotApplicable') { return 'NOT-APPLICABLE | ' + (($Findings | ForEach-Object Code) -join ', ') }
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
    $f = Get-AddinFindings
    $fix = @($f | Where-Object Kind -eq 'Fixable').Count
    $att = @($f | Where-Object Kind -eq 'Attention').Count
    $code = if ($fix -gt 0 -or ($ReportAttentionAsIssue -and $att -gt 0)) { 1 } else { 0 }
    [pscustomobject]@{ ExitCode = $code; Output = (Format-Findings $f) }
}

if ($MyInvocation.InvocationName -ne '.') { Complete-Rem { Invoke-RemDetection } }
