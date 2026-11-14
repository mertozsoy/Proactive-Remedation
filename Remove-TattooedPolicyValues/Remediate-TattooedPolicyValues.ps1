<#
.SYNOPSIS
  Remediation script for explicitly listed retired machine policy values.

.DESCRIPTION
  Requires retirement approval and a time limited deletion window. Exports each
  parent key before removing only an exact matching value and verifies absence.
  Exits 0 when listed values are absent, 1 when blocked, mismatched or unsuccessful.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RetiredValues = @()
$EnableRemediation = $false
$ApprovalExpiresUtc = ''

$PackageName = 'TattooedPolicyValues'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Assert-TargetList {
    $seen = @{}
    foreach ($target in $RetiredValues) {
        if ($target -isnot [hashtable]) { throw 'Invalid target format.' }
        if ([string]$target.Path -notmatch '^HKLM:\\SOFTWARE\\Policies\\[A-Za-z0-9 _.-]+(\\[A-Za-z0-9 _.-]+)*$' -or
            @(([string]$target.Path).Split('\') | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            throw 'Only explicit HKLM SOFTWARE Policies subkeys are allowed.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$target.Name) -or [string]$target.Name -match '[\\*?\[\]\r\n]') {
            throw 'An exact value name is required.'
        }
        if ($target.Kind -notin @('DWord', 'String') -or -not $target.ContainsKey('Data') -or $null -eq $target.Data) {
            throw 'Expected type and data are required.'
        }
        if ($target.Kind -eq 'DWord') { [void][int]::Parse([string]$target.Data, [Globalization.CultureInfo]::InvariantCulture) }
        if ($target.SourcesRetired -isnot [bool]) { throw 'SourcesRetired must be Boolean.' }
        $identity = '{0}|{1}' -f $target.Path, $target.Name
        if ($seen.ContainsKey($identity)) { throw 'Duplicate target.' }
        $seen[$identity] = $true
    }
}

function Get-TargetState {
    param([hashtable]$Target)
    if (-not (Test-Path -LiteralPath $Target.Path -ErrorAction Stop)) { return 'Absent' }
    $key = Get-Item -LiteralPath $Target.Path -ErrorAction Stop
    try {
        if ($key.GetValueNames() -notcontains $Target.Name) { return 'Absent' }
        if ($key.GetValueKind($Target.Name).ToString() -ne $Target.Kind) { return 'Mismatch' }
        $data = $key.GetValue($Target.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($Target.Kind -eq 'DWord') {
            if ([int]$data -ne [int]$Target.Data) { return 'Mismatch' }
        }
        elseif (-not [string]::Equals([string]$data, [string]$Target.Data, [StringComparison]::Ordinal)) { return 'Mismatch' }
        return 'Match'
    }
    finally { $key.Close() }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error | Reason=Requires64BitPowerShell' }
    if ($RetiredValues.Count -eq 0) { Exit-Script 0 'NotApplicable | Targets=0' }
    Assert-TargetList
    $pending = @()
    $mismatched = 0
    $unapproved = 0
    foreach ($target in $RetiredValues) {
        $state = Get-TargetState -Target $target
        if ($state -eq 'Match') {
            $pending += $target
            if (-not $target.SourcesRetired) { $unapproved++ }
        }
        elseif ($state -eq 'Mismatch') { $mismatched++ }
    }
    if ($mismatched -gt 0 -or $unapproved -gt 0) {
        Exit-Script 1 "Blocked | Mismatched=$mismatched; Unapproved=$unapproved; Removed=0"
    }
    if ($pending.Count -eq 0) { Exit-Script 0 'Healthy | Remaining=0' }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Matching=$($pending.Count); Removed=0" }
    $expires = [datetime]::ParseExact($ApprovalExpiresUtc, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
    if ($expires -le [datetime]::UtcNow -or $expires -gt [datetime]::UtcNow.AddDays(7)) {
        Exit-Script 1 'Blocked | Reason=ApprovalWindowMustBeWithin7Days; Removed=0'
    }
    $backupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup\TattooedPolicyValues'
    New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    $removed = 0
    foreach ($target in $pending) {
        if ([datetime]::UtcNow -ge $expires) { throw 'Approval expired during cleanup.' }
        if ((Get-TargetState -Target $target) -ne 'Match') { throw 'Target changed before backup.' }
        $backup = Join-Path $backupRoot (([guid]::NewGuid().ToString('N')) + '.reg')
        $nativeKey = 'HKEY_LOCAL_MACHINE\' + $target.Path.Substring(6)
        & $regExe export $nativeKey $backup /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup -ErrorAction Stop)) { throw 'Registry export failed.' }
        if ((Get-Item -LiteralPath $backup -ErrorAction Stop).Length -eq 0) { throw 'Registry export is empty.' }
        if ((Get-TargetState -Target $target) -ne 'Match') { throw 'Target changed after backup.' }
        Write-IRTLog "Backup=$([IO.Path]::GetFileName($backup)); TargetIndex=$([array]::IndexOf($RetiredValues, $target))"
        Remove-ItemProperty -LiteralPath $target.Path -Name $target.Name -Force -ErrorAction Stop
        if ((Get-TargetState -Target $target) -ne 'Absent') { throw 'Value removal verification failed.' }
        $removed++
    }
    $remaining = @($RetiredValues | Where-Object { (Get-TargetState -Target $_) -ne 'Absent' }).Count
    if ($remaining -gt 0) { Exit-Script 1 "Failed | Removed=$removed; Remaining=$remaining" }
    Exit-Script 0 "Fixed | Removed=$removed; Remaining=0"
}
catch { Exit-Script 1 "Error: CleanupIncomplete | Type=$($_.Exception.GetType().Name)" }
