<#
.SYNOPSIS
  Remediation script for unwanted new Outlook on Windows 11 24H2 and later.

.DESCRIPTION
  Removes Microsoft.OutlookForWindows provisioning and all-user registrations,
  then verifies both inventories. App removal can delete local application data.
  AllowAppRemoval defaults to false and requires explicit administrator approval.
  Exits 0 only if absent or not applicable, 1 if deferred, failed or still present.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowAppRemoval = $false
$MinimumWindowsBuild = 26100
$VerificationAttempts = 3
$VerificationDelaySeconds = 5

$PackageName = 'NewOutlook'
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
    if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    if (-not $AllowAppRemoval) { Exit-Script 1 "Deferred | Reason=AppRemovalNotApproved; $summary" }
    $running = @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -eq 'olk' })
    if ($running.Count -gt 0) { Exit-Script 1 "Deferred | Reason=NewOutlookRunning; $summary" }
    if (@($installed | Where-Object { $_.NonRemovable }).Count -gt 0) {
        Exit-Script 1 "Failed | Reason=NonRemovableApp; $summary"
    }
    foreach ($app in $provisioned) {
        $result = Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $app.PackageName -ErrorAction Stop
        Write-IRTLog ('Deprovisioned | RestartNeeded={0}' -f $result.RestartNeeded)
    }
    $remaining = @(Get-AppxPackage -AllUsers -Name 'Microsoft.OutlookForWindows' -ErrorAction Stop |
        Where-Object { $_.Name -eq 'Microsoft.OutlookForWindows' } |
        Sort-Object -Property PackageFullName -Unique)
    foreach ($app in $remaining) {
        Remove-AppxPackage -AllUsers -Package $app.PackageFullName -Confirm:$false -ErrorAction Stop
        Write-IRTLog 'Removed | Target=Microsoft.OutlookForWindows'
    }
    for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
        $installed = @(Get-AppxPackage -AllUsers -Name 'Microsoft.OutlookForWindows' -ErrorAction Stop |
            Where-Object { $_.Name -eq 'Microsoft.OutlookForWindows' })
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
            Where-Object { $_.DisplayName -eq 'Microsoft.OutlookForWindows' })
        $summary = 'Installed={0}; Provisioned={1}' -f $installed.Count, $provisioned.Count
        if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) { Exit-Script 0 "Fixed | $summary" }
        if ($attempt -lt $VerificationAttempts) { Start-Sleep -Seconds $VerificationDelaySeconds }
    }
    Exit-Script 1 "Failed | Reason=AppStillPresent; $summary"
}
catch { Exit-Script 1 ('Failed | Reason=RemovalOrInventoryError; HResult={0}' -f $_.Exception.HResult) }
