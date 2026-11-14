<#
.SYNOPSIS
  Detection script for explicitly listed retired machine policy values.

.DESCRIPTION
  Compares exact registry names, types and data with an administrator supplied list.
  Exits 1 when listed values remain or inspection fails, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RetiredValues = @()

$PackageName = 'TattooedPolicyValues'
$Phase = 'Detect'
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
    $matching = 0
    $mismatched = 0
    $unapproved = 0
    foreach ($target in $RetiredValues) {
        $state = Get-TargetState -Target $target
        if ($state -eq 'Match') {
            $matching++
            if (-not $target.SourcesRetired) { $unapproved++ }
        }
        elseif ($state -eq 'Mismatch') { $mismatched++ }
    }
    if ($matching -gt 0 -or $mismatched -gt 0) {
        Exit-Script 1 "Drift | Matching=$matching; Mismatched=$mismatched; Unapproved=$unapproved"
    }
    Exit-Script 0 "Healthy | Remaining=0; Targets=$($RetiredValues.Count)"
}
catch { Exit-Script 1 "Error: InspectionFailed | Type=$($_.Exception.GetType().Name)" }
