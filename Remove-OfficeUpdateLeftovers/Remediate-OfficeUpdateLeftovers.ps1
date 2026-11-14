<#
.SYNOPSIS
  Remediation script for retired Office update management settings.

.DESCRIPTION
  Requires explicit confirmation that Office management has been retired.
  Backs up affected keys, disables leftover OfficeMgmtCOM and removes only
  exact approved source or channel values. Verifies the registry changes.
  Does not restart services or install Office updates. Exits 1 when blocked
  or verification fails, 0 when fixed or no candidates exist.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RetiredManagementConfirmed = $false
$RetiredUpdatePaths = @()
$RetiredUpdateBranches = @()

$PackageName = 'OfficeUpdateLeftovers'
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
function Get-OfficeOverride {
    foreach ($location in $Locations) {
        if (-not (Test-Path -LiteralPath $location.Path -ErrorAction Stop)) { continue }
        $key = Get-Item -LiteralPath $location.Path -ErrorAction Stop
        try {
            foreach ($name in $location.Names) {
                if ($key.GetValueNames() -notcontains $name) { continue }
                $value = $key.GetValue($name)
                $kind = $key.GetValueKind($name).ToString()
                $candidate = $false
                $approved = $false
                if ($name -eq 'OfficeMgmtCOM') {
                    if ($location.Id -eq 'Configuration') {
                        $candidate = ([string]$value -ieq 'True') -or ([string]$value -eq '1')
                        $approved = $candidate -and $kind -eq 'String'
                    } else {
                        $candidate = [string]$value -eq '1'
                        $approved = $candidate -and $kind -eq 'DWord'
                    }
                } elseif (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $candidate = $true
                    if ($name -eq 'UpdateBranch') {
                        $approved = $kind -eq 'String' -and $RetiredUpdateBranches -contains [string]$value
                    } else {
                        $approved = $kind -eq 'String' -and $RetiredUpdatePaths -contains [string]$value
                    }
                }
                if ($candidate) {
                    [pscustomobject]@{ Id = $location.Id; Path = $location.Path; Name = $name; Approved = $approved; Value = $value; Kind = $kind }
                }
            }
        } finally { $key.Close() }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $configuration = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (-not (Test-Path -LiteralPath $configuration)) { Exit-Script 0 'NotApplicable | Reason=ClickToRunAbsent' }
    $Locations = @(
        @{ Id = 'Configuration'; Path = $configuration; Names = @('OfficeMgmtCOM', 'UpdateUrl') }
        @{ Id = 'Policy64'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate'; Names = @('OfficeMgmtCOM', 'UpdatePath', 'UpdateBranch') }
        @{ Id = 'Policy32'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Office\16.0\Common\OfficeUpdate'; Names = @('OfficeMgmtCOM', 'UpdatePath', 'UpdateBranch') }
    )
    $found = @(Get-OfficeOverride)
    if ($found.Count -eq 0) { Exit-Script 0 'Healthy | Candidates=0; Scope=UpdateOverrides' }
    if (-not $RetiredManagementConfirmed) { Exit-Script 1 'Blocked | Reason=OwnershipNotConfirmed; Changed=0' }
    if (@(Get-Service -Name 'CcmExec' -ErrorAction SilentlyContinue).Count -gt 0) {
        Exit-Script 1 'Blocked | Reason=ConfigMgrClientPresent; Changed=0'
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\cloud\Office\16.0\Common\OfficeUpdate') {
        Exit-Script 1 'Blocked | Reason=CloudPolicyPresent; Changed=0'
    }
    if (@($found | Where-Object { -not $_.Approved }).Count -gt 0) {
        Exit-Script 1 'Blocked | Reason=UnapprovedValueOrType; Changed=0'
    }
    $backupFolder = Join-Path $env:ProgramData ('IntuneRemediations\Backup\OfficeUpdateLeftovers\' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $backupFolder -ItemType Directory -Force
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    foreach ($location in $Locations) {
        if (@($found | Where-Object { $_.Id -eq $location.Id }).Count -eq 0) { continue }
        $nativePath = $location.Path -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
        $backupFile = Join-Path $backupFolder ($location.Id + '.reg')
        & $regExe export $nativePath $backupFile /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) {
            Exit-Script 1 'Failed | Reason=BackupFailed; Changed=0'
        }
    }
    foreach ($item in $found) {
        $key = Get-Item -LiteralPath $item.Path
        try {
            if ($key.GetValueNames() -notcontains $item.Name -or
                $key.GetValueKind($item.Name).ToString() -ne $item.Kind -or
                [string]$key.GetValue($item.Name) -cne [string]$item.Value) {
                Exit-Script 1 'Failed | Reason=ConcurrentChange; Review=RegistryBackup'
            }
        } finally { $key.Close() }
        if ($item.Name -eq 'OfficeMgmtCOM') {
            if ($item.Id -eq 'Configuration') {
                Set-ItemProperty -LiteralPath $item.Path -Name $item.Name -Value 'False'
            } else {
                Set-ItemProperty -LiteralPath $item.Path -Name $item.Name -Value 0
            }
        } else {
            Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name
        }
    }
    $remaining = @(Get-OfficeOverride)
    if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | Remaining=$($remaining.Count); Review=PolicyOwnership" }
    foreach ($item in $found) {
        $key = Get-Item -LiteralPath $item.Path
        try {
            if ($item.Name -eq 'OfficeMgmtCOM') {
                $expected = '0'
                if ($item.Id -eq 'Configuration') { $expected = 'False' }
                if ([string]$key.GetValue($item.Name) -ine $expected) { throw 'VerificationFailed' }
            } elseif ($key.GetValueNames() -contains $item.Name) { throw 'VerificationFailed' }
        } finally { $key.Close() }
    }
    Exit-Script 0 "Fixed | Changed=$($found.Count); Verified=Registry; COM=NextServiceStart; Updates=NotVerified"
} catch { Exit-Script 1 'Error: RemediationFailed | Review=RegistryBackup; Updates=NotVerified' }
