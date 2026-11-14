<#
.SYNOPSIS
  Detection script for retired Office update management settings.

.DESCRIPTION
  Reports OfficeMgmtCOM and source or channel overrides. Exits 1 for candidates,
  0 when no candidates exist or Click-to-Run is absent. Values alone do not
  establish whether a policy is retired. No update source data is logged.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RetiredManagementConfirmed = $false
$RetiredUpdatePaths = @()
$RetiredUpdateBranches = @()

$PackageName = 'OfficeUpdateLeftovers'
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
                    [pscustomobject]@{ Id = $location.Id; Path = $location.Path; Name = $name; Approved = $approved }
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
    $cloudManaged = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\cloud\Office\16.0\Common\OfficeUpdate'
    $configMgr = @(Get-Service -Name 'CcmExec' -ErrorAction SilentlyContinue).Count -gt 0
    $unapproved = @($found | Where-Object { -not $_.Approved }).Count
    $names = ($found | ForEach-Object { '{0}:{1}' -f $_.Id, $_.Name }) -join ','
    Exit-Script 1 "Drift | Candidates=$($found.Count); Unapproved=$unapproved; OwnershipConfirmed=$RetiredManagementConfirmed; ConfigMgr=$configMgr; CloudPolicy=$cloudManaged; Values=$names"
} catch { Exit-Script 1 'Error: InspectionFailed | Review=RegistryAndServiceAccess' }
