<#
.SYNOPSIS
  Detection script for Microsoft 365 Apps subscription activation state.

.DESCRIPTION
  Reads the Click-to-Run inventory and skips volume licensed installs and shared computer activation. Then inspects the per-user vNext license store. Exits 1 if the store is missing, empty, holds zero byte files or only stale license files, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedProducts = @()
$TokenMaxAgeDays  = 45
$InventoryKey     = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Inventory\Office\16.0'
$ClickToRunKey    = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$LicensingKey     = 'HKCU:\Software\Microsoft\Office\16.0\Common\Licensing\LicensingNext'
$LicenseRoot      = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses'

$PackageName = 'M365AppsActivation'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}
function Get-OfficeInfo {
    $releaseIds = ''
    $version    = ''
    if (Test-Path -LiteralPath $InventoryKey) {
        $inventory  = Get-ItemProperty -LiteralPath $InventoryKey -ErrorAction SilentlyContinue
        $releaseIds = [string]$inventory.OfficeProductReleaseIds
        $version    = [string]$inventory.OfficePackageVersion
    }
    $products = @()
    if (-not [string]::IsNullOrWhiteSpace($releaseIds)) {
        $products = @($releaseIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    [pscustomobject]@{
        Product      = ($products -join ',')
        Version      = $version
        Subscription = (@($products | Where-Object { $_ -match 'O365|Microsoft365' }).Count -gt 0)
        Volume       = (@($products | Where-Object { $_ -match 'Volume$' }).Count -gt 0)
    }
}
function Get-LicenseState {
    $state = [pscustomobject]@{
        RootExists = $false
        Files      = @()
        Total      = 0
        Empty      = 0
        Stale      = 0
        NewestDays = -1
    }
    if (-not (Test-Path -LiteralPath $LicenseRoot -PathType Container)) { return $state }
    $state.RootExists = $true
    $files   = @()
    $folders = @(Get-ChildItem -LiteralPath $LicenseRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[0-9]+$' })
    foreach ($folder in $folders) {
        $files += @(Get-ChildItem -LiteralPath $folder.FullName -File -Force -ErrorAction SilentlyContinue)
    }
    if ($files.Count -eq 0) {
        $files = @(Get-ChildItem -LiteralPath $LicenseRoot -File -Force -ErrorAction SilentlyContinue)
    }
    $limit        = (Get-Date).AddDays(-$TokenMaxAgeDays)
    $state.Files  = $files
    $state.Total  = $files.Count
    $state.Empty  = @($files | Where-Object { $_.Length -eq 0 }).Count
    $state.Stale  = @($files | Where-Object { $_.Length -gt 0 -and $_.LastWriteTime -lt $limit }).Count
    if ($files.Count -gt 0) {
        $newest = ($files | Sort-Object LastWriteTime -Descending)[0]
        $state.NewestDays = [int]((Get-Date) - $newest.LastWriteTime).TotalDays
    }
    $state
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($identity -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User' }
    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $office = Get-OfficeInfo
    if ([string]::IsNullOrWhiteSpace($office.Product)) { Exit-Script 0 'NotApplicable | Office=NotInstalled' }
    if ($office.Volume) { Exit-Script 0 "NotApplicable | Product=$($office.Product); Activation=VolumeLicense" }
    if (-not $office.Subscription) { Exit-Script 0 "NotApplicable | Product=$($office.Product); Activation=Perpetual" }
    if ($ExpectedProducts.Count -gt 0) {
        $ids   = @($office.Product -split ',')
        $match = @($ExpectedProducts | Where-Object { $ids -contains $_ })
        if ($match.Count -eq 0) { Exit-Script 0 "NotApplicable | Product=$($office.Product); Expected=NotInstalled" }
    }

    $config = Get-ItemProperty -LiteralPath $ClickToRunKey -ErrorAction SilentlyContinue
    if ($null -ne $config -and [string]$config.SharedComputerLicensing -eq '1') {
        Exit-Script 0 "NotApplicable | Product=$($office.Product); SCA=Enabled"
    }

    $state = Get-LicenseState
    $activatedBefore = Test-Path -LiteralPath $LicensingKey
    if ($state.Total -eq 0 -and -not $activatedBefore) { Exit-Script 0 "NotApplicable | Product=$($office.Product); License=NeverActivated" }
    if (-not $state.RootExists -or $state.Total -eq 0) { Exit-Script 1 "Drift | Product=$($office.Product); License=Missing" }
    if ($state.Empty -gt 0) { Exit-Script 1 "Drift | Product=$($office.Product); Tokens=$($state.Total); Empty=$($state.Empty)" }
    if ($state.Stale -eq $state.Total) { Exit-Script 1 "Drift | Product=$($office.Product); Tokens=$($state.Total); NewestDays=$($state.NewestDays)" }
    Exit-Script 0 "Healthy | Product=$($office.Product); Tokens=$($state.Total); NewestDays=$($state.NewestDays)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
