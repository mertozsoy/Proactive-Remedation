<#
.SYNOPSIS
  Detection script for the Windows 10 Extended Security Updates license state.

.DESCRIPTION
  Reads the OS build and queries the Software Licensing service for the ESU product of the configured ESU year. Exits 1 when the ESU key is missing or not activated, 0 when it is licensed or when the device is out of scope.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EsuYear             = 0
$BuildWindows10_22H2 = 19045
$BuildWindows11      = 22000
$EsuYearAnchorDay    = 15
$EsuActivationIds    = @{
    1 = 'f520e45e-7413-4a34-a497-d2765967d094'
    2 = '1043add5-23b1-4afb-9a0f-64343c8f3f8d'
    3 = '83d49986-add3-41d7-ba33-87c7bfb5c0fb'
}

$PackageName = 'Windows10Esu'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$VersionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$ProductKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions'

function Get-OSBuild {
    $raw   = [string](Get-ItemProperty -LiteralPath $VersionKey -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue).CurrentBuildNumber
    $build = [int]$raw
    if ($build -lt 10240) { throw "OS build number not readable: $raw" }
    $build
}

function Get-EsuYearFromDate {
    $now    = Get-Date
    $anchor = Get-Date -Year $now.Year -Month 10 -Day $EsuYearAnchorDay -Hour 0 -Minute 0 -Second 0
    if ($now -lt $anchor) { $index = $now.Year - 2025 } else { $index = ($now.Year + 1) - 2025 }
    if ($index -lt 1) { $index = 1 }
    if ($index -gt 3) { $index = 3 }
    $index
}

function Get-EsuTarget {
    $year = [int]$EsuYear
    if ($year -lt 1 -or $year -gt 3) { $year = Get-EsuYearFromDate }
    [pscustomobject]@{ Year = $year; ActivationId = $EsuActivationIds[$year] }
}

function Get-EsuProduct {
    param([string]$ActivationId)
    Get-CimInstance -ClassName SoftwareLicensingProduct -Filter ("ID='{0}'" -f $ActivationId) -ErrorAction Stop | Select-Object -First 1
}

try {
    $productType = [string](Get-ItemProperty -LiteralPath $ProductKey -Name 'ProductType' -ErrorAction SilentlyContinue).ProductType
    if ($productType -and $productType -ne 'WinNT') { Exit-Script 0 "NotApplicable | ProductType=$productType" }

    $build = Get-OSBuild
    if ($build -ge $BuildWindows11) { Exit-Script 0 "NotApplicable | Build=$build; ESU=Windows11" }
    if ($build -ne $BuildWindows10_22H2) { Exit-Script 0 "NotApplicable | Build=$build; ESU=Requires22H2" }

    $target  = Get-EsuTarget
    $product = Get-EsuProduct -ActivationId $target.ActivationId
    if (-not $product) { Exit-Script 1 "Missing | Year=$($target.Year); Key=NotInstalled; Build=$build" }

    $status = [int]$product.LicenseStatus
    if ($status -ne 1) { Exit-Script 1 "NotActivated | Year=$($target.Year); LicenseStatus=$status; Build=$build" }

    Exit-Script 0 "Healthy | Year=$($target.Year); LicenseStatus=Licensed; Build=$build"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
