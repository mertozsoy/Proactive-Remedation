<#
.SYNOPSIS
  Detection script for shared computer activation licensing in Microsoft 365 Apps.

.DESCRIPTION
  Reads the Click-to-Run shared computer licensing switch and inspects the licensing token cache of the signed-in user. Exits 1 if the cache folder is missing, empty or holds only unusable tokens, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$OfficeVersion   = '16.0'
$TokenMaxAgeDays = 25
$ClickToRunKey   = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

$PackageName = 'SharedComputerActivation'
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
function Get-TokenFolder { param($Config)
    $override     = [string]$Config.SCLCacheOverride
    $overridePath = [string]$Config.SCLCacheOverrideDirectory
    if ($override -eq '1' -and -not [string]::IsNullOrWhiteSpace($overridePath)) { return $overridePath }
    Join-Path $env:LOCALAPPDATA "Microsoft\Office\$OfficeVersion\Licensing"
}
function Get-TokenState { param([string]$Folder)
    $exists = Test-Path -LiteralPath $Folder -PathType Container
    $files  = @()
    if ($exists) { $files = @(Get-ChildItem -LiteralPath $Folder -File -Force -ErrorAction SilentlyContinue) }
    $valid    = @($files | Where-Object { $_.Length -gt 0 })
    $limit    = (Get-Date).AddDays(-$TokenMaxAgeDays)
    $unusable = @($files | Where-Object { $_.Length -eq 0 -or $_.LastWriteTime -lt $limit })
    $age      = 0
    if ($valid.Count -gt 0) {
        $newest = ($valid | Sort-Object LastWriteTime -Descending)[0]
        $age    = [int]((Get-Date) - $newest.LastWriteTime).TotalDays
    }
    [pscustomobject]@{ Folder = $Folder; Exists = $exists; Total = $files.Count; Unusable = $unusable.Count; AgeDays = $age }
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($identity -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User' }
    if (-not (Test-Path -LiteralPath $ClickToRunKey)) { Exit-Script 0 'NotApplicable | Office=NotInstalled' }
    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $config = Get-ItemProperty -LiteralPath $ClickToRunKey -ErrorAction Stop
    if ([string]$config.SharedComputerLicensing -ne '1') { Exit-Script 0 'NotApplicable | SCA=Disabled; Required=SharedComputerLicensing' }

    $folder = Get-TokenFolder -Config $config
    $token  = Get-TokenState -Folder $folder
    $cache  = 'Default'
    if ([string]$config.SCLCacheOverride -eq '1') { $cache = 'Override' }

    if (-not $token.Exists) { Exit-Script 1 "Drift | SCA=Enabled; Cache=$cache; Folder=Missing" }
    if ($token.Total -eq 0) { Exit-Script 1 "Drift | SCA=Enabled; Cache=$cache; Tokens=0" }
    if ($token.Unusable -gt 0) { Exit-Script 1 "Drift | SCA=Enabled; Cache=$cache; Tokens=$($token.Total); Unusable=$($token.Unusable); NewestDays=$($token.AgeDays)" }
    Exit-Script 0 "Healthy | SCA=Enabled; Cache=$cache; Tokens=$($token.Total); NewestDays=$($token.AgeDays)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
