<#
.SYNOPSIS
  Remediation script for Windows activation.

.DESCRIPTION
  Retries activation without changing the product key.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'WindowsActivation'
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

$WindowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'

try {
    $done = @()
    foreach ($svc in 'sppsvc', 'ClipSVC') {
        $s = Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction SilentlyContinue
        if ($s -and $s.StartMode -eq 'Disabled') {

            & sc.exe config $svc start= demand | Out-Null
            $done += "$svc re-enabled"
        }
    }

    foreach ($t in 'EnableLicenseAcquisition', 'LicenseAcquisition') {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Subscription\' -TaskName $t -ErrorAction SilentlyContinue
        if ($task) { Start-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue; $done += "$t started" }
    }

    $slmgr = Join-Path $env:WINDIR 'System32\slmgr.vbs'
    $out = & cscript.exe //NoLogo $slmgr /ato 2>&1
    Write-IRTLog "slmgr /ato: $($out -join ' ')"
    Start-Sleep -Seconds 10

    $status = (Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='$WindowsAppId' AND PartialProductKey IS NOT NULL" |
               Sort-Object LicenseStatus | Select-Object -First 1).LicenseStatus
    $done += "LicenseStatus now $status"
    if ($status -eq 1) { Exit-Script 0 ($done -join '; ') }
    Exit-Script 1 ("Still not activated: $(($out | Select-Object -Last 1)) | " + ($done -join '; '))
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
