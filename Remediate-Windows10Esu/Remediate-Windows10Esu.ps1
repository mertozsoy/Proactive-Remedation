<#
.SYNOPSIS
  Remediation script that installs and activates the Windows 10 ESU key.

.DESCRIPTION
  Reads the ESU MAK from the configured variable or from a local key file, installs the key for the configured ESU year and activates it online. Verifies the result through the Software Licensing service. Exits 0 when the ESU product is licensed, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EsuYear             = 0
$EsuMak              = ''
$EsuMakFile          = Join-Path $env:ProgramData 'IntuneRemediations\ESU\esu-mak.txt'
$InstallKey          = $true
$ActivateKey         = $true
$ActivationRetries   = 4
$ActivationWaitSecs  = 5
$BuildWindows10_22H2 = 19045
$BuildWindows11      = 22000
$EsuYearAnchorDay    = 15
$EsuActivationIds    = @{
    1 = 'f520e45e-7413-4a34-a497-d2765967d094'
    2 = '1043add5-23b1-4afb-9a0f-64343c8f3f8d'
    3 = '83d49986-add3-41d7-ba33-87c7bfb5c0fb'
}

$PackageName = 'Windows10Esu'
$Phase       = 'Remediate'
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
$SlmgrPath  = Join-Path $env:SystemRoot 'System32\slmgr.vbs'

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

function Get-ProductKey {
    if ($EsuMak) { return ([string]$EsuMak).Trim() }
    if (Test-Path -LiteralPath $EsuMakFile) {
        $value = Get-Content -LiteralPath $EsuMakFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($value) { return ([string]$value).Trim() }
    }
    ''
}

function Invoke-Slmgr {
    param([string[]]$Arguments)
    $null = & "$env:SystemRoot\System32\cscript.exe" //nologo $SlmgrPath @Arguments 2>&1
    [int]$LASTEXITCODE
}

try {
    $productType = [string](Get-ItemProperty -LiteralPath $ProductKey -Name 'ProductType' -ErrorAction SilentlyContinue).ProductType
    if ($productType -and $productType -ne 'WinNT') { Exit-Script 0 "NotApplicable | ProductType=$productType" }

    $build = Get-OSBuild
    if ($build -ge $BuildWindows11) { Exit-Script 0 "NotApplicable | Build=$build; ESU=Windows11" }
    if ($build -ne $BuildWindows10_22H2) { Exit-Script 0 "NotApplicable | Build=$build; ESU=Requires22H2" }

    $target  = Get-EsuTarget
    $product = Get-EsuProduct -ActivationId $target.ActivationId
    if ($product -and [int]$product.LicenseStatus -eq 1) {
        Exit-Script 0 "Healthy | Year=$($target.Year); LicenseStatus=Licensed; Key=Installed"
    }

    $key = Get-ProductKey
    if (-not $key) { Exit-Script 1 "Failed | Year=$($target.Year); EsuMak=NotConfigured; Source=VariableOrFile" }
    if ($key -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') {
        Exit-Script 1 "Failed | Year=$($target.Year); EsuMak=InvalidFormat; Expected=25Characters"
    }

    $installed = $false
    if ($product) { $installed = $true }

    if (-not $installed) {
        if (-not $InstallKey) { Exit-Script 1 "Failed | Year=$($target.Year); Key=NotInstalled; InstallKey=Disabled" }
        Write-IRTLog "Installing ESU key for year $($target.Year)"
        $ipkExit = Invoke-Slmgr -Arguments @('/ipk', $key)
        Write-IRTLog "slmgr /ipk return code $ipkExit"
        if ($ipkExit -ne 0) { Exit-Script 1 "Failed | Year=$($target.Year); Step=InstallKey; ReturnCode=$ipkExit; Hint=PrerequisiteUpdateMissing" }
        $product = Get-EsuProduct -ActivationId $target.ActivationId
        if (-not $product) { Exit-Script 1 "Failed | Year=$($target.Year); Step=InstallKey; Product=NotFound" }
    }

    if (-not $ActivateKey) { Exit-Script 1 "Failed | Year=$($target.Year); Key=Installed; ActivateKey=Disabled" }

    Write-IRTLog "Activating ESU key for year $($target.Year)"
    $atoExit = Invoke-Slmgr -Arguments @('/ato', $target.ActivationId)
    Write-IRTLog "slmgr /ato return code $atoExit"

    for ($i = 0; $i -lt $ActivationRetries; $i++) {
        $product = Get-EsuProduct -ActivationId $target.ActivationId
        if ($product -and [int]$product.LicenseStatus -eq 1) {
            Exit-Script 0 "Fixed | Year=$($target.Year); LicenseStatus=Licensed; Activation=Online"
        }
        Start-Sleep -Seconds $ActivationWaitSecs
    }

    $status = 'Unknown'
    if ($product) { $status = [int]$product.LicenseStatus }
    Exit-Script 1 "Failed | Year=$($target.Year); Step=ActivateKey; LicenseStatus=$status; ReturnCode=$atoExit"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
