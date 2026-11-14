<#
.SYNOPSIS
  Remediation script that disables LLMNR and NetBIOS over TCP/IP.

.DESCRIPTION
  Sets the LLMNR policy value to 0 and turns NetBIOS off on every network adapter.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$CheckNetBIOS = $true

$PackageName = 'LLMNRNetBIOS'
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

try {
    $done = @()
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name EnableMulticast -Value 0 -Type DWord -ErrorAction Stop
    $done += 'LLMNR disabled'

    if ($CheckNetBIOS) {
        $n = 0
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction Stop | ForEach-Object {
            if ((Get-ItemProperty $_.PSPath -Name NetbiosOptions -ErrorAction SilentlyContinue).NetbiosOptions -ne 2) {
                Set-ItemProperty -Path $_.PSPath -Name NetbiosOptions -Value 2 -Type DWord; $n++
            }
        }
        $done += "NetBIOS disabled on $n interface(s)"
    }
    Exit-Script 0 ($done -join '; ')
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
