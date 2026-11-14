<#
.SYNOPSIS
  Detection script for NTLMv1 based SSO (MS-CHAPv2) readiness.

.DESCRIPTION
  Reads the BlockNtlmv1SSO setting and related events. Exits 1 if a time limited exception has to be applied or removed.

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

$script:RemId    = 'REM-005'
$script:LogDir   = if ($env:ProgramData) { Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs' } else { $null }
$script:StateKey = 'HKLM:\SOFTWARE\IntuneRemediations\REM-005'

$ExceptionApprovedUntil = ''
$MaxExceptionDays       = 90

$ReportAttentionAsIssue = $false

$RevertUnmanagedAudit   = $false
$EventLookbackDays      = 14
$MinimumBuild           = 26100

$LsaKey    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
$ValueName = 'BlockNtlmv1SSO'

function Get-RemRegValue {
    param([string]$Path, [string]$Name)
    $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.$Name }
    return $null
}
function Get-RemOsBuild { [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild }
function Test-RemCredentialGuardRunning {
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        return [bool](@($dg.SecurityServicesRunning) -contains 1)
    } catch { return $false }
}
function Get-RemNtlmEventCounts {
    param([int]$Days)
    $r = @{ Audit = 0; Blocked = 0 }
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-NTLM/Operational'; Id = 4024, 4025; StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 1000 -ErrorAction Stop
        $r.Audit   = @($ev | Where-Object Id -eq 4024).Count
        $r.Blocked = @($ev | Where-Object Id -eq 4025).Count
    } catch { }
    $r
}
function Test-RemMsChapXml {
    param([string]$Xml)

    return ($Xml -match '<(\w+:)?Type[^>]*>\s*26\s*</' -or $Xml -match 'NonEapAuthMethod>\s*MSCHAPv2')
}
function Get-RemMsChapProfiles {

    $found = New-Object System.Collections.Generic.List[string]
    $stores = @(
        @{ Tag = 'WLAN'; Path = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces' }
        @{ Tag = 'LAN';  Path = Join-Path $env:ProgramData 'Microsoft\dot3svc\Profiles\Interfaces' }
    )
    foreach ($store in $stores) {
        if (-not (Test-Path -LiteralPath $store.Path)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $store.Path -Filter *.xml -Recurse -ErrorAction SilentlyContinue)) {
            $xml = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($xml -and (Test-RemMsChapXml $xml)) {
                $name = if ($xml -match '<name>([^<]+)</name>') { $Matches[1] } else { $f.BaseName }
                $found.Add(('{0}:{1}' -f $store.Tag, $name))
            }
        }
    }
    foreach ($vpn in @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue)) {
        $eap = if ($vpn.EapConfigXmlStream) { $vpn.EapConfigXmlStream.OuterXml } else { '' }
        if (@($vpn.AuthenticationMethod) -contains 'MSChapv2' -or (Test-RemMsChapXml $eap)) { $found.Add('VPN:' + $vpn.Name) }
    }

    $pbks = @(Get-ChildItem -Path (Join-Path $env:SystemDrive 'Users\*\AppData\Roaming\Microsoft\Network\Connections\Pbk\rasphone.pbk') -ErrorAction SilentlyContinue)
    foreach ($pbk in $pbks) {
        $entry = $null
        foreach ($line in (Get-Content -LiteralPath $pbk.FullName -ErrorAction SilentlyContinue)) {
            if ($line -match '^\[(.+)\]$') { $entry = $Matches[1] }
            elseif ($line -match '^CustomAuthKey=(25|26)$' -and $entry) {

                $found.Add(('PBK:{0}{1}' -f $entry, $(if ($Matches[1] -eq '25') { '(PEAP-inner-unknown)' } else { '' })))
            }
        }
    }
    @($found | Select-Object -Unique)
}
function ConvertTo-RemDate {
    param([string]$Text)
    $t = [datetime]::MinValue
    if ($Text -and [datetime]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) { return $t }
    return $null
}
function Get-RemApproval {

    $d = ConvertTo-RemDate $ExceptionApprovedUntil
    if (-not $d) { return $null }
    $d = $d.Date.AddDays(1).AddSeconds(-1)
    if ($d -gt (Get-Date).AddDays($MaxExceptionDays)) { return 'TooLong' }
    return $d
}
function Get-Bucket { param([int]$n) if ($n -eq 0) { '0' } elseif ($n -le 10) { '1-10' } else { '>10' } }

function Get-NtlmFindings {
    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($Kind, $Code) $findings.Add([pscustomobject]@{ Kind = $Kind; Code = $Code }) }
    $now = Get-Date

    if ((Get-RemOsBuild) -lt $MinimumBuild) { & $add 'NotApplicable' 'Build<24H2'; return $findings }

    $cg      = Test-RemCredentialGuardRunning
    $value   = Get-RemRegValue $LsaKey $ValueName
    $mode    = if ($null -eq $value) { 'Enforce(default)' } elseif ([int]$value -eq 0) { 'Audit' } else { 'Enforce' }
    $events  = Get-RemNtlmEventCounts -Days $EventLookbackDays
    $prof    = @(Get-RemMsChapProfiles)
    $recEnd  = ConvertTo-RemDate (Get-RemRegValue $script:StateKey 'ExceptionUntil')
    $approve = Get-RemApproval

    & $add 'Info' ('Mode={0}; CredentialGuard={1}; Blocked4025={2}; Audit4024={3}' -f $mode, $(if ($cg) { 'Running' } else { 'Off' }), (Get-Bucket $events.Blocked), (Get-Bucket $events.Audit))
    if ($prof.Count) { & $add 'Info' ('MsChapV2Profiles=' + ($prof -join ',')) }

    $approveValid = $approve -is [datetime]
    if ($recEnd) {

        $effectiveEnd = if ($approveValid) { $approve } else { $recEnd }
        if ($now -gt $effectiveEnd) { & $add 'Fixable' ('Exception=Expired({0:yyyy-MM-dd})' -f $effectiveEnd); return $findings }
        if ($null -eq $value -or [int]$value -ne 0) {

            & $add 'Attention' ('ExceptionOverridden(BlockNtlmv1SSO={0})' -f $(if ($null -eq $value) { 'absent' } else { $value }))
            return $findings
        }
        if ($approveValid -and $approve -gt $recEnd) { & $add 'Fixable' ('Exception=Extend(until {0:yyyy-MM-dd})' -f $approve); return $findings }
        & $add 'Info' ('Exception=Active(until {0:yyyy-MM-dd})' -f $effectiveEnd)
        return $findings
    }
    if ($mode -eq 'Audit') {
        if ($RevertUnmanagedAudit) { & $add 'Fixable' 'AuditMode=Unmanaged(revert)' } else { & $add 'Attention' 'AuditMode=Unmanaged(set outside this package, no end date)' }
    }

    if ($cg) {
        if ($prof.Count) { & $add 'Attention' 'MsChapV2WithCredentialGuard(SSO not possible; migrate to EAP-TLS)' }
        return $findings
    }
    $riskProfiles = @($prof | Where-Object { $_ -notlike '*(PEAP-inner-unknown)' })
    $atRisk = ($mode -ne 'Audit') -and ($riskProfiles.Count -gt 0 -or $events.Blocked -gt 0)
    if (-not $atRisk) { return $findings }

    if ($approve -is [datetime] -and $approve -gt $now) { & $add 'Fixable' ('Exception=Apply(until {0:yyyy-MM-dd})' -f $approve) }
    elseif ($approve -eq 'TooLong') { & $add 'Attention' ('AtRisk; ExceptionRejected(more than {0} days)' -f $MaxExceptionDays) }
    else { & $add 'Attention' 'AtRisk(MS-CHAPv2 SSO blocked; migrate to EAP-TLS/PEAP-TLS or approve a time-boxed exception)' }
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
    $f = Get-NtlmFindings
    $fix = @($f | Where-Object Kind -eq 'Fixable').Count
    $att = @($f | Where-Object Kind -eq 'Attention').Count
    $code = if ($fix -gt 0 -or ($ReportAttentionAsIssue -and $att -gt 0)) { 1 } else { 0 }
    [pscustomobject]@{ ExitCode = $code; Output = (Format-Findings $f) }
}

if ($MyInvocation.InvocationName -ne '.') { Complete-Rem { Invoke-RemDetection } }
