<#
.SYNOPSIS
  Remediation script that sets AC sleep and display timeouts on the active power plan.

.DESCRIPTION
  Writes the target plugged-in sleep and display timeouts to the active power plan with powercfg and verifies them. Exits 0 if the values match, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SleepTimeoutAcMinutes   = 0
$DisplayTimeoutAcMinutes = 60

$PackageName = 'AcPowerTimeouts'
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

$PolicyRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$Settings = @(
    [pscustomobject]@{ Name = 'Sleep';   SubGroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; TargetSeconds = $SleepTimeoutAcMinutes * 60 }
    [pscustomobject]@{ Name = 'Display'; SubGroup = '7516b95f-f776-4464-8c53-06167f40cc99'; Setting = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'; TargetSeconds = $DisplayTimeoutAcMinutes * 60 }
)

function Get-ActiveSchemeId {
    $plan = Get-CimInstance -Namespace 'root\cimv2\power' -ClassName Win32_PowerPlan -Filter 'IsActive=True' -ErrorAction Stop | Select-Object -First 1
    if ($plan.InstanceID -match '\{([0-9a-fA-F-]{36})\}') { return $Matches[1] }
    return $null
}

function Get-AcTimeoutState { param([string]$SchemeId)
    foreach ($item in $Settings) {
        $policy  = (Get-ItemProperty -LiteralPath (Join-Path $PolicyRoot $item.Setting) -Name ACSettingIndex -ErrorAction SilentlyContinue).ACSettingIndex
        $filter  = "InstanceID='Microsoft:PowerSettingDataIndex\\{$SchemeId}\\AC\\{$($item.Setting)}'"
        $current = (Get-CimInstance -Namespace 'root\cimv2\power' -ClassName Win32_PowerSettingDataIndex -Filter $filter -ErrorAction SilentlyContinue).SettingIndexValue
        if ($null -ne $policy)       { $state = 'Policy' }
        elseif ($null -eq $current)  { $state = 'NotPresent' }
        elseif ([int64]$current -eq $item.TargetSeconds) { $state = 'Match' }
        else                         { $state = 'Mismatch' }
        [pscustomobject]@{ Name = $item.Name; SubGroup = $item.SubGroup; Setting = $item.Setting; TargetSeconds = $item.TargetSeconds; CurrentSeconds = $current; State = $state }
    }
}

function Format-TimeoutState { param($State)
    ($State | ForEach-Object { '{0}Min={1}({2})' -f $_.Name, ($(if ($null -ne $_.CurrentSeconds) { [math]::Round($_.CurrentSeconds / 60, 0) } else { 'n/a' })), $_.State }) -join '; '
}

try {
    $scheme = Get-ActiveSchemeId
    if (-not $scheme) { Exit-Script 0 'NotApplicable | Active power plan not found' }

    foreach ($item in @(Get-AcTimeoutState -SchemeId $scheme | Where-Object { $_.State -eq 'Mismatch' })) {
        $null = & powercfg.exe /setacvalueindex $scheme $item.SubGroup $item.Setting $item.TargetSeconds 2>&1
        Write-IRTLog "$($item.Name): $($item.CurrentSeconds)s -> $($item.TargetSeconds)s (powercfg exit $LASTEXITCODE)"
    }
    $null = & powercfg.exe /setactive $scheme 2>&1

    $state   = @(Get-AcTimeoutState -SchemeId $scheme)
    $summary = Format-TimeoutState -State $state
    if (@($state | Where-Object { $_.State -eq 'Mismatch' }).Count -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Applied | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
