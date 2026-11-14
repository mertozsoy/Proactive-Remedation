<#
.SYNOPSIS
  Detection script for temporary Wi-Fi profiles left on the device after provisioning.

.DESCRIPTION
  Reads the machine WLAN profile store and lists profiles that match the configured temporary names or patterns. Exits 1 if a temporary profile is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TemporaryProfileNames = @('Onboarding', 'Provisioning', 'TempWifi')
$TemporaryNamePatterns = @('(?i)^(onboarding|provisioning|temp)[-_ ]?wifi')
$KeepProfileNames      = @()

$PackageName = 'TemporaryWifiProfile'
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

$ProfileStore = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces'

function Get-WlanProfileInfo {
    $profiles = @()
    if (-not (Test-Path -LiteralPath $ProfileStore)) { return $profiles }
    foreach ($interfaceDir in @(Get-ChildItem -LiteralPath $ProfileStore -Directory -ErrorAction SilentlyContinue)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $interfaceDir.FullName -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
            try {
                $xml = [xml](Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop)
                $nameNode = $xml.SelectSingleNode("/*[local-name()='WLANProfile']/*[local-name()='name']")
                if ($null -eq $nameNode) { continue }
                $authNode = $xml.SelectSingleNode("/*[local-name()='WLANProfile']/*[local-name()='MSM']/*[local-name()='security']/*[local-name()='authEncryption']/*[local-name()='authentication']")
                $auth = 'unknown'
                if ($null -ne $authNode) { $auth = $authNode.InnerText }
                $profiles += [pscustomobject]@{
                    Name           = $nameNode.InnerText
                    Authentication = $auth
                    File           = $file.FullName
                    Interface      = $interfaceDir.Name
                }
            }
            catch { Write-IRTLog "Profile XML could not be read: $($file.FullName)" 'WARN' }
        }
    }
    $profiles
}

function Test-TemporaryProfile { param([string]$Name)
    foreach ($keep in $KeepProfileNames) {
        if ($Name -eq $keep) { return $false }
    }
    foreach ($temp in $TemporaryProfileNames) {
        if ($Name -eq $temp) { return $true }
    }
    foreach ($pattern in $TemporaryNamePatterns) {
        if ($Name -match $pattern) { return $true }
    }
    $false
}

try {
    if (-not (Test-Path -LiteralPath $ProfileStore)) { Exit-Script 0 'NotApplicable | WLAN profile store not found' }

    $all = @(Get-WlanProfileInfo)
    if ($all.Count -eq 0) { Exit-Script 0 'NotApplicable | No WLAN profiles found' }

    $temp = @($all | Where-Object { Test-TemporaryProfile -Name $_.Name })
    if ($temp.Count -eq 0) { Exit-Script 0 "Healthy | Profiles=$($all.Count); Temporary=0" }

    $names = (@($temp | Sort-Object Name -Unique | ForEach-Object { $_.Name }) -join ',')
    $auth  = (@($temp | Sort-Object Name -Unique | ForEach-Object { $_.Authentication }) -join ',')
    Exit-Script 1 "Drift | Profiles=$($temp.Count); Names=$names; Auth=$auth"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
