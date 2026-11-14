<#
.SYNOPSIS
  Detection script for local user accounts that are missing from the approved list.

.DESCRIPTION
  Compares every local user account with the approved list and skips built-in
  accounts by relative identifier. Exits 1 if at least one unapproved account is
  enabled, 0 otherwise or when the approved list is empty.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedAccounts = @()
$ExcludedNames = @('defaultuser0')
$MinimumRid = 1000

$PackageName = 'UnapprovedLocalAccounts'
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

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired' }
    if ($ApprovedAccounts.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=ApprovedListEmpty' }

    $approved = @($ApprovedAccounts | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $excluded = @($ExcludedNames | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $unapproved = @()
    foreach ($account in @(Get-LocalUser)) {
        if (-not $account.SID) { continue }
        $sid = $account.SID.Value
        if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { continue }
        if ([int64]($sid.Split('-')[-1]) -lt $MinimumRid) { continue }
        if ($account.PrincipalSource -and [string]$account.PrincipalSource -ne 'Local') { continue }
        if ($excluded -contains $account.Name.ToLowerInvariant()) { continue }
        if ($approved -contains $account.Name.ToLowerInvariant()) { continue }
        $unapproved += $account
    }

    $enabled = @($unapproved | Where-Object { $_.Enabled })
    if ($enabled.Count -eq 0) {
        Exit-Script 0 "Healthy | Unapproved=$($unapproved.Count); Enabled=0"
    }
    Exit-Script 1 "Drift | Unapproved=$($unapproved.Count); Enabled=$($enabled.Count); ApprovedList=$($approved.Count)"
}
catch { Exit-Script 1 ('Error: InspectionFailed | HResult={0}' -f $_.Exception.HResult) }
