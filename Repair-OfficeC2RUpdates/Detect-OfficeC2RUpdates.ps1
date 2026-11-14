<#
.SYNOPSIS
  Detects Microsoft 365 Apps Click-to-Run update source and task problems.

.DESCRIPTION
  Checks an optional approved update source and minimum build plus update task health.
  Exits 1 for drift or an inspection failure, 0 for healthy or excluded installations.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedUpdateUrl = ''
$MinimumVersion = ''
$MaxTaskAgeDays = 7

$PackageName = 'OfficeC2RUpdates'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ($MaxTaskAgeDays -lt 1) { Exit-Script 1 'Failed | Reason=InvalidTaskAge' }
    if ($MinimumVersion -and $MinimumVersion -notmatch '^16\.0\.\d+\.\d+$') { Exit-Script 1 'Failed | Reason=InvalidMinimumVersion' }
    if ($ApprovedUpdateUrl) {
        $approvedUri = [uri]$ApprovedUpdateUrl
        if (-not $approvedUri.IsAbsoluteUri -or $approvedUri.Scheme -ne 'https' -or $approvedUri.UserInfo -or $approvedUri.Query -or $approvedUri.Fragment) {
            Exit-Script 1 'Failed | Reason=ApprovedSourceMustBeHttpsWithoutCredentialsOrQuery'
        }
    }
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $inventoryPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Inventory\Office\16.0'
    if (-not (Test-Path -LiteralPath $configPath)) { Exit-Script 0 'NotApplicable | Reason=NoClickToRun' }
    $config = Get-ItemProperty -LiteralPath $configPath
    $policyPaths = @('HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate', 'HKLM:\SOFTWARE\Policies\Microsoft\cloud\office\16.0\Common\officeupdate')
    foreach ($path in $policyPaths) {
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Property.Count -gt 0) {
            Exit-Script 0 'NotApplicable | Reason=ManagedOfficePolicy; Action=ReviewCentralManagement'
        }
    }
    if ([string]$config.OfficeMgmtCOM -match '^(true|1)$' -or (Get-Service -Name CcmExec -ErrorAction SilentlyContinue)) {
        Exit-Script 0 'NotApplicable | Reason=ConfigurationManager; Action=ReviewCentralManagement'
    }
    if (-not (Test-Path -LiteralPath $inventoryPath)) { Exit-Script 1 'Failed | Reason=OfficeInventoryMissing' }
    $inventory = Get-ItemProperty -LiteralPath $inventoryPath
    if (($inventory.OfficeProductReleaseIds -join ',') -notmatch '(^|[,;\s])(O365ProPlusRetail|O365BusinessRetail)($|[,;\s])') {
        Exit-Script 0 'NotApplicable | Reason=NotMicrosoft365Apps'
    }
    if ([string]$inventory.OfficePackageVersion -notmatch '^16\.0\.\d+\.\d+$') { Exit-Script 1 'Failed | Reason=OfficeInventoryVersionInvalid' }
    $version = [version]$inventory.OfficePackageVersion
    $task = Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office Automatic Updates 2.0'
    $info = $task | Get-ScheduledTaskInfo
    $reasons = @()
    if ($ApprovedUpdateUrl -and ([string]$config.UpdateUrl).TrimEnd('/') -ne $ApprovedUpdateUrl.TrimEnd('/')) { $reasons += 'SourceMismatch' }
    if ($task.State -eq 'Disabled') { $reasons += 'TaskDisabled' }
    if ($task.State -ne 'Running') {
        if ($info.LastRunTime -lt (Get-Date).AddDays(-$MaxTaskAgeDays)) { $reasons += 'TaskStale' }
        if ($info.LastTaskResult -ne 0) { $reasons += 'TaskFailure' }
    }
    if ($MinimumVersion -and $version -lt [version]$MinimumVersion) { $reasons += 'BelowMinimum' }
    if ($reasons.Count -gt 0) { Exit-Script 1 "Drift | Reasons=$($reasons -join ','); Version=$version; Task=$($task.State)" }
    Exit-Script 0 "Healthy | Version=$version; Task=$($task.State); Scope=ConfiguredChecksOnly"
}
catch { Exit-Script 1 "Failed | Reason=InspectionError; ErrorType=$($_.Exception.GetType().Name)" }
