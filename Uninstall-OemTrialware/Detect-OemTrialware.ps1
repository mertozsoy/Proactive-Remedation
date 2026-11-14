<#
.SYNOPSIS
  Detection script for selected OEM trialware.

.DESCRIPTION
  Reads machine uninstall registrations in both registry views. Exits 1 when a selected product remains, 0 otherwise. Does not query Win32_Product.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetNames = @('HP Wolf Security', 'HP Wolf Security Application Support', 'HP Security Update Service', 'McAfee', 'McAfee LiveSafe', 'McAfee Total Protection', 'WebAdvisor by McAfee', 'Dell SupportAssist', 'Dell SupportAssist Remediation')
$ExcludedProductCodes = @()

$PackageName = 'OemTrialware'
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

function Get-TargetProduct {
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
            $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ($TargetNames -notcontains [string]$entry.DisplayName) { continue }
            if ($ExcludedProductCodes -contains $key.PSChildName) { continue }
            $isMsi = $entry.WindowsInstaller -eq 1 -and $key.PSChildName -match '^\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}$'
            [pscustomobject]@{
                Name = [string]$entry.DisplayName
                ProductCode = $key.PSChildName
                IsMsi = $isMsi
                Security = [string]$entry.DisplayName -notlike 'Dell SupportAssist*'
            }
        }
    }
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $products = @(Get-TargetProduct)
    if ($products.Count -eq 0) { Exit-Script 0 'Healthy | Targets=0' }
    $names = ($products.Name | Sort-Object -Unique) -join ','
    $unsupported = @($products | Where-Object { -not $_.IsMsi }).Count
    Exit-Script 1 "Drift | Targets=$($products.Count); NonMsi=$unsupported; Apps=$names"
}
catch { Exit-Script 1 "Error: Failed | Reason=InventoryError; Type=$($_.Exception.GetType().Name)" }
