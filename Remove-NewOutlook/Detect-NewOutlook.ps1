<#
.SYNOPSIS
  Detection script for unwanted new Outlook on Windows 11 24H2 and later.

.DESCRIPTION
  Checks all users and online provisioning for Microsoft.OutlookForWindows.
  Exits 1 if the app remains or inventory fails, 0 if absent or not applicable.
  Assign only to devices where no user requires new Outlook.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumWindowsBuild = 26100

$PackageName = 'NewOutlook'
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
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt $MinimumWindowsBuild) {
        Exit-Script 0 'NotApplicable | Requires=Windows11-24H2OrLaterClient'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $installed = @(Get-AppxPackage -AllUsers -Name 'Microsoft.OutlookForWindows' -ErrorAction Stop |
        Where-Object { $_.Name -eq 'Microsoft.OutlookForWindows' })
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
        Where-Object { $_.DisplayName -eq 'Microsoft.OutlookForWindows' })
    $summary = 'Installed={0}; Provisioned={1}' -f $installed.Count, $provisioned.Count
    if ($installed.Count -gt 0 -or $provisioned.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Failed | Reason=InventoryError; HResult={0}' -f $_.Exception.HResult) }
