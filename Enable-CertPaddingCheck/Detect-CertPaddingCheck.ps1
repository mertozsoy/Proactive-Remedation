<#
.SYNOPSIS
  Detection script for the WinVerifyTrust EnableCertPaddingCheck setting.

.DESCRIPTION
  Reads EnableCertPaddingCheck under HKLM\SOFTWARE\Microsoft\Cryptography\Wintrust\Config and, on 64-bit Windows, under HKLM\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config. Microsoft documents the value as REG_SZ and the required data as 1. Exits 1 if a required location is missing or does not hold 1, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$NativeKey  = 'HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config'
$Wow6432Key = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
$ValueName  = 'EnableCertPaddingCheck'

$PackageName = 'CertPaddingCheck'
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

function Get-PaddingValue {
    param([string]$KeyPath)
    if (-not (Test-Path -LiteralPath $KeyPath)) { return 'Missing' }
    $item = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction Stop
    $prop = $item.PSObject.Properties[$ValueName]
    if ($null -eq $prop) { return 'Missing' }
    $raw = [string]$prop.Value
    if ($raw -eq '1') { return '1' }
    if ($raw -eq '0') { return '0' }
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'Empty' }
    return 'Other'
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 ('NotApplicable | ProductType=' + $os.ProductType) }

    $native = Get-PaddingValue -KeyPath $NativeKey
    $wow    = 'Skipped'
    if ([Environment]::Is64BitOperatingSystem) {
        $wow = Get-PaddingValue -KeyPath $Wow6432Key
    }

    $text = 'Native=' + $native + '; Wow6432=' + $wow
    if ($native -ne '1') { Exit-Script 1 ('Drift | ' + $text) }
    if ([Environment]::Is64BitOperatingSystem -and $wow -ne '1') { Exit-Script 1 ('Drift | ' + $text) }
    Exit-Script 0 ('Healthy | ' + $text)
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
