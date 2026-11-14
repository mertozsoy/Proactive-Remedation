<#
.SYNOPSIS
  Remediation script that removes temporary Wi-Fi profiles left after provisioning.

.DESCRIPTION
  Deletes the profiles that match the configured temporary names or patterns with netsh, then checks that they are gone. Exits 0 if no temporary profile is left, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation      = $false
$RemoveConnectedProfile = $false
$TemporaryProfileNames  = @('Onboarding', 'Provisioning', 'TempWifi')
$TemporaryNamePatterns  = @('(?i)^(onboarding|provisioning|temp)[-_ ]?wifi')
$KeepProfileNames       = @()

$PackageName = 'TemporaryWifiProfile'
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

function Get-ConnectedWifiName {
    $names = @()
    foreach ($connection in @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
        $adapter = Get-NetAdapter -Name $connection.InterfaceAlias -ErrorAction SilentlyContinue
        if ($null -eq $adapter) { continue }
        if ($adapter.PhysicalMediaType -like '*802.11*') { $names += $connection.Name }
    }
    $names
}

try {
    if (-not (Test-Path -LiteralPath $ProfileStore)) { Exit-Script 0 'NotApplicable | WLAN profile store not found' }

    $temp = @(Get-WlanProfileInfo | Where-Object { Test-TemporaryProfile -Name $_.Name })
    if ($temp.Count -eq 0) { Exit-Script 0 'Healthy | Temporary=0' }

    $names = @($temp | Sort-Object Name -Unique | ForEach-Object { $_.Name })
    $nameList = $names -join ','

    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Names=$nameList; EnableRemediation=false" }

    $connected = @(Get-ConnectedWifiName)
    $removed = 0
    $skipped = 0
    foreach ($name in $names) {
        if ((-not $RemoveConnectedProfile) -and ($connected -contains $name)) {
            Write-IRTLog "Profile skipped because it is connected: $name" 'WARN'
            $skipped++
            continue
        }
        $null = & netsh.exe wlan delete profile "name=$name" 2>&1
        $code = $LASTEXITCODE
        Write-IRTLog "netsh delete profile $name exit code $code"
        if ($code -eq 0) { $removed++ }
    }

    $remaining = @()
    for ($i = 0; $i -lt 5; $i++) {
        $remaining = @(Get-WlanProfileInfo | Where-Object { Test-TemporaryProfile -Name $_.Name })
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }

    if ($remaining.Count -gt 0) {
        $left = @($remaining | Sort-Object Name -Unique | ForEach-Object { $_.Name }) -join ','
        Exit-Script 1 "Failed | Removed=$removed; Skipped=$skipped; Remaining=$($remaining.Count); Names=$left"
    }
    Exit-Script 0 "Fixed | Removed=$removed; Skipped=$skipped; Names=$nameList; Remaining=0"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
