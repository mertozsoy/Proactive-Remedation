<#
.SYNOPSIS
  Detection script for a hybrid Entra joined device that is not enrolled in Intune.

.DESCRIPTION
  Reads the dsregcmd state and the Intune enrollment keys. Exits 1 when the device is domain joined and Entra joined but has no active Intune enrollment, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnrollmentsRoot          = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$IntuneProviderId         = 'MS DM Server'
$AutoEnrollTaskPath       = '\Microsoft\Windows\EnterpriseMgmt\'
$AutoEnrollTaskNameMatch  = '*automatically enrolling in MDM*'

$PackageName = 'MDMEnrollment'
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

function Get-DsregState {
    $state = @{}
    foreach ($line in (& dsregcmd.exe /status)) {
        if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$') { $state[$Matches[1]] = $Matches[2] }
    }
    $state
}

function Get-ActiveIntuneEnrollment {
    @(Get-ChildItem -LiteralPath $EnrollmentsRoot -ErrorAction SilentlyContinue | Where-Object {
        $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $item.ProviderID -eq $IntuneProviderId -and $item.EnrollmentState -eq 1
    })
}

function Get-AutoEnrollTask {
    @(Get-ScheduledTask -TaskPath $AutoEnrollTaskPath -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -like $AutoEnrollTaskNameMatch
    })
}

try {
    $dsreg = Get-DsregState
    if ($dsreg['DomainJoined'] -ne 'YES' -or $dsreg['AzureAdJoined'] -ne 'YES') {
        Exit-Script 0 "NotApplicable | DomainJoined=$($dsreg['DomainJoined']); AzureAdJoined=$($dsreg['AzureAdJoined'])"
    }

    $enrollments = @(Get-ActiveIntuneEnrollment)
    if ($enrollments.Count -gt 0) {
        Exit-Script 0 "Healthy | IntuneEnrollment=$($enrollments.Count); DomainJoined=YES; AzureAdJoined=YES"
    }

    $taskState = 'Missing'
    $tasks = @(Get-AutoEnrollTask)
    if ($tasks.Count -gt 0) { $taskState = ($tasks | ForEach-Object { $_.State }) -join ',' }

    Exit-Script 1 "NotEnrolled | DomainJoined=YES; AzureAdJoined=YES; AzureAdPrt=$($dsreg['AzureAdPrt']); IntuneEnrollment=0; AutoEnrollTask=$taskState"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
