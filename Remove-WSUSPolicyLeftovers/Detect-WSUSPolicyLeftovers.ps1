<#
.SYNOPSIS
  Detection script for leftover WSUS and Windows Update policy values.

.DESCRIPTION
  Checks for WSUS server settings and other values that block Windows Update for Business. Exits 1 if any are found.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SkipIfConfigMgrClient = $true

$PackageName = 'WSUSPolicyLeftovers'
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

try {
    if ($SkipIfConfigMgrClient -and (Get-Service -Name CcmExec -ErrorAction SilentlyContinue)) { Exit-Script 0 'Skipped | ConfigMgr client present (co-management)' }

    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $p  = Get-ItemProperty $wu -ErrorAction SilentlyContinue
    $au = Get-ItemProperty (Join-Path $wu 'AU') -ErrorAction SilentlyContinue
    $f  = @()
    foreach ($n in 'WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate') { if ($p.$n) { $f += "$n=$($p.$n)" } }
    if ($p.DoNotConnectToWindowsUpdateInternetLocations -eq 1) { $f += 'DoNotConnectToWUInternet=1' }
    if ($p.DisableWindowsUpdateAccess -eq 1)                   { $f += 'DisableWindowsUpdateAccess=1' }
    if ($au.UseWUServer -eq 1)                                 { $f += 'UseWUServer=1' }
    if ($au.NoAutoUpdate -eq 1)                                { $f += 'NoAutoUpdate=1' }

    if ($f) { Exit-Script 1 "Leftovers | $($f -join '; ')" }
    Exit-Script 0 'Clean'
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
