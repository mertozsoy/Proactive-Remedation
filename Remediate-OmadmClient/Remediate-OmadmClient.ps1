<#
.SYNOPSIS
  Remediation script for omadmclient.exe processes that stayed running too long.

.DESCRIPTION
  Terminates omadmclient.exe instances that are older than the threshold. The newest
  instance is kept when it is younger than the threshold so an active sync is not
  interrupted. Verifies that no stuck instance remains and exits 1 if one does.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$StuckMinutes = 30
$MaxInstances = 1
$VerifySeconds = 5
$EnableRemediation = $true

$PackageName = 'OmadmClient'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-OmadmInstance { param([string]$Name)
    $now = Get-Date
    @(Get-CimInstance -ClassName Win32_Process -Filter "Name = '$Name'" -ErrorAction Stop | ForEach-Object {
        $age = -1
        if ($_.CreationDate) {
            $age = [int][math]::Floor(($now - $_.CreationDate).TotalMinutes)
        }
        [pscustomobject]@{
            ProcessId    = [int]$_.ProcessId
            CreationDate = $_.CreationDate
            AgeMinutes   = $age
        }
    })
}
try {
    if ($StuckMinutes -lt 5 -or $VerifySeconds -lt 1 -or $VerifySeconds -gt 60) { throw 'InvalidThreshold' }
    $clientPath = Join-Path $env:SystemRoot 'System32\omadmclient.exe'
    if (-not (Test-Path -LiteralPath $clientPath -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | OmaDmClient=Missing' }

    $instances = @(Get-OmadmInstance -Name 'omadmclient.exe')
    $stuck = @($instances | Where-Object { $_.AgeMinutes -ge $StuckMinutes })
    if ($stuck.Count -eq 0) {
        Exit-Script 0 "Healthy | Instances=$($instances.Count); Stuck=0; ThresholdMinutes=$StuckMinutes"
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Stuck=$($stuck.Count); ThresholdMinutes=$StuckMinutes; Enabled=False"
    }

    $young = @($instances | Where-Object { $_.AgeMinutes -lt $StuckMinutes } | Sort-Object CreationDate -Descending)
    $protectedId = 0
    if ($young.Count -gt 0) { $protectedId = $young[0].ProcessId }

    $targets = @($stuck | Where-Object { $_.ProcessId -ne $protectedId })
    if ($targets.Count -eq 0) {
        Exit-Script 0 "Healthy | Instances=$($instances.Count); Stuck=0; ProtectedPid=$protectedId"
    }

    $terminated = 0
    $failed = 0
    foreach ($target in $targets) {
        try {
            Stop-Process -Id $target.ProcessId -Force -ErrorAction Stop
            $terminated++
            Write-IRTLog ('Terminated | ProcessId={0}; AgeMinutes={1}' -f $target.ProcessId, $target.AgeMinutes)
        }
        catch {
            $failed++
            Write-IRTLog ('TerminateFailed | ProcessId={0}; Type={1}' -f $target.ProcessId, $_.Exception.GetType().Name) 'WARN'
        }
    }

    Start-Sleep -Seconds $VerifySeconds
    $remaining = @(Get-OmadmInstance -Name 'omadmclient.exe' | Where-Object { $_.AgeMinutes -ge $StuckMinutes })
    $protectedText = 'None'
    if ($protectedId -ne 0) { $protectedText = "$protectedId" }

    if ($remaining.Count -gt 0) {
        $remainingIds = (@($remaining | Select-Object -First 5 | ForEach-Object { $_.ProcessId }) -join ',')
        Exit-Script 1 "Failed | Terminated=$terminated; Failed=$failed; Remaining=$($remaining.Count); Pids=$remainingIds"
    }

    Exit-Script 0 "Fixed | Terminated=$terminated; Failed=$failed; Remaining=0; ProtectedPid=$protectedText; Retry=NextSync"
}
catch { Exit-Script 1 "Error | Type=$($_.Exception.GetType().Name); Action=InspectOmadmClient" }
