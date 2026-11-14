<#
.SYNOPSIS
  Detection script for LLMNR and NetBIOS over TCP/IP.

.DESCRIPTION
  Checks the LLMNR policy value and the NetBIOS setting of every network adapter. Exits 1 if either is still enabled, 0 if both are off.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$CheckNetBIOS = $true

$PackageName = 'LLMNRNetBIOS'
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
    $issues = @()
    $llmnr = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -ErrorAction SilentlyContinue).EnableMulticast
    if ($llmnr -ne 0) { $issues += "LLMNR(EnableMulticast=$llmnr)" }

    if ($CheckNetBIOS) {
        $bad = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue | Where-Object {
            (Get-ItemProperty $_.PSPath -Name NetbiosOptions -ErrorAction SilentlyContinue).NetbiosOptions -ne 2
        }
        if ($bad) { $issues += "NetBIOS enabled on $(@($bad).Count) interface(s)" }
    }

    if ($issues) { Exit-Script 1 "NonCompliant | $($issues -join '; ')" }
    Exit-Script 0 'Compliant | LLMNR and NetBIOS disabled'
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
