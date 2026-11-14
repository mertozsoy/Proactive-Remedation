<#
.SYNOPSIS
  Detection script for classic Outlook compose and reply fonts.

.DESCRIPTION
  Compares four binary font values with an administrator-supplied reference.
  Exits 1 for drift or invalid configuration, 0 for a match or an excluded scope.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedFontLabel = 'Arial 10'
$ExpectedFontHex = [ordered]@{
    ComposeFontSimple = ''
    ComposeFontComplex = ''
    ReplyFontSimple = ''
    ReplyFontComplex = ''
}
$ExternallyManaged = $false

$PackageName = 'OutlookComposeFont'
$Phase = 'Detect'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message)
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Message) -ErrorAction Stop
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 2000) }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-FontDrift {
    param([System.Collections.IDictionary]$Expected)
    $key = Get-Item -LiteralPath $script:FontPath -ErrorAction Stop
    try {
        foreach ($name in $Expected.Keys) {
            if ($key.GetValueNames() -notcontains $name) { $name; continue }
            if ($key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::Binary) { $name; continue }
            $actual = [Convert]::ToBase64String([byte[]]$key.GetValue($name))
            if ($actual -cne [Convert]::ToBase64String($Expected[$name])) { $name }
        }
    }
    finally { $key.Close() }
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }
    $FontPath = 'HKCU:\Software\Microsoft\Office\16.0\Common\MailSettings'
    if (-not (Test-Path -LiteralPath 'HKCU:\Software\Microsoft\Office\16.0\Outlook')) {
        Exit-Script 0 'NotApplicable | ClassicOutlook=NotInitialized'
    }
    if ($ExternallyManaged) { Exit-Script 0 'NotApplicable | Font=ExternallyManaged' }
    foreach ($root in @('HKCU:\Software\Policies\Microsoft\Office\16.0', 'HKLM:\Software\Policies\Microsoft\Office\16.0', 'HKCU:\Software\Policies\Microsoft\Cloud\Office\16.0', 'HKLM:\Software\Policies\Microsoft\Cloud\Office\16.0')) {
        if (Test-Path -LiteralPath "$root\Common\MailSettings") {
            Exit-Script 0 'NotApplicable | MailSettings=PolicyPresent'
        }
    }
    $expected = [ordered]@{}
    foreach ($name in $ExpectedFontHex.Keys) {
        $hex = [string]$ExpectedFontHex[$name]
        if ($hex -notmatch '^\s*[0-9A-Fa-f]{2}(?:\s*,\s*[0-9A-Fa-f]{2})+\s*$') {
            Exit-Script 1 "Failed | Configuration=ReferenceHexRequired; Value=$name"
        }
        $expected[$name] = [byte[]]@($hex.Split(',') | ForEach-Object { [Convert]::ToByte($_.Trim(), 16) })
    }
    if (-not (Test-Path -LiteralPath $FontPath)) {
        Exit-Script 1 'Drift | Values=4; Reason=MailSettingsMissing'
    }
    $drift = @(Get-FontDrift -Expected $expected)
    if ($drift.Count -gt 0) { Exit-Script 1 "Drift | Values=$($drift.Count); Names=$($drift -join ',')" }
    Exit-Script 0 "Healthy | Values=4; Baseline=$ExpectedFontLabel"
}
catch { Exit-Script 1 ('Error: Failed | Operation=Detect; HResult={0}' -f $_.Exception.HResult) }
