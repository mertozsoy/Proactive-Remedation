<#
.SYNOPSIS
  Detection script for unwanted Office Click-to-Run products.

.DESCRIPTION
  Compares installed product IDs with an explicit removal list. Exits 1 for unwanted products or unreadable inventory, 0 otherwise. Language inventory is outside this check.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RemoveProductIds = @('HomeBusiness2021Retail', 'HomeBusiness2024Retail', 'HomeStudent2021Retail', 'Home2024Retail', 'O365HomePremRetail')
$RequiredSuiteIds = @('O365ProPlusRetail', 'O365BusinessRetail', 'O365ProPlusEEANoTeamsRetail', 'O365BusinessEEANoTeamsRetail')

$PackageName = 'ExtraOfficeProducts'
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
function Get-OfficeProductId {
    $raw = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -Name ProductReleaseIds -ErrorAction Stop
    $ids = @(([string]$raw -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($ids.Count -eq 0 -or @($ids | Where-Object { $_ -notmatch '^[A-Za-z0-9]+$' }).Count -gt 0) {
        throw 'Invalid product inventory'
    }
    $ids
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    if (@($RemoveProductIds | Where-Object { $_ -notmatch '^[A-Za-z0-9]+$' -or $_ -match '^(O365ProPlus|O365Business|Visio|Project)' -or $RequiredSuiteIds -contains $_ }).Count -gt 0) {
        Exit-Script 1 'Failed | Reason=UnsafeRemovalList'
    }
    if (-not (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration')) {
        Exit-Script 0 'NotApplicable | Reason=NoClickToRun; LanguageAudit=NotCovered'
    }
    $installed = @(Get-OfficeProductId)
    Write-IRTLog ('InstalledProducts=' + ($installed -join ','))
    $targets = @($installed | Where-Object { $RemoveProductIds -contains $_ })
    $suitePresent = @($installed | Where-Object { $RequiredSuiteIds -contains $_ }).Count -gt 0
    if ($targets.Count -eq 0) { Exit-Script 0 'Healthy | UnwantedProducts=0; LanguageAudit=NotCovered' }
    Exit-Script 1 "Drift | UnwantedProducts=$($targets.Count); Products=$($targets -join ','); RequiredSuitePresent=$suitePresent; LanguageAudit=NotCovered"
}
catch { Exit-Script 1 "Failed | Reason=InventoryError; ErrorType=$($_.Exception.GetType().Name)" }
