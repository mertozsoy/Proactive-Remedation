<#
.SYNOPSIS
  Remediation script for leftover WSUS and Windows Update policy values.

.DESCRIPTION
  Removes the blocking values and restarts the Windows Update service.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'WSUSPolicyLeftovers'
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
    $wu  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $bak = Join-Path $env:ProgramData 'IntuneRemediations'
    if (-not (Test-Path $bak)) { New-Item -Path $bak -ItemType Directory -Force | Out-Null }
    $file = Join-Path $bak ("WindowsUpdatePolicy_{0:yyyyMMdd_HHmmss}.reg" -f (Get-Date))
    & reg.exe export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' $file /y 2>$null | Out-Null

    $removed = @()
    foreach ($n in 'WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate', 'DoNotConnectToWindowsUpdateInternetLocations', 'DisableWindowsUpdateAccess') {
        if ($null -ne (Get-ItemProperty $wu -Name $n -ErrorAction SilentlyContinue)) { Remove-ItemProperty $wu -Name $n -ErrorAction Stop; $removed += $n }
    }
    foreach ($n in 'UseWUServer', 'NoAutoUpdate') {
        if ($null -ne (Get-ItemProperty (Join-Path $wu 'AU') -Name $n -ErrorAction SilentlyContinue)) { Remove-ItemProperty (Join-Path $wu 'AU') -Name $n -ErrorAction Stop; $removed += "AU\$n" }
    }

    Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Exit-Script 0 "Removed: $(if ($removed) { $removed -join ', ' } else { 'nothing' }). Backup: $file"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
