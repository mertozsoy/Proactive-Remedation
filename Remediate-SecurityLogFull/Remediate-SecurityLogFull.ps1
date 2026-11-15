<#
.SYNOPSIS
  Remediation script that puts the Security event log back into circular mode.

.DESCRIPTION
  Switches the Security channel from Retain to Circular so new events overwrite
  the oldest ones again. Optionally clears the log and resets a CrashOnAuditFail
  value of 2 to 1. A Retention value set by policy is reported and not changed.
  Exits 0 after successful verification and 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$LogName                = 'Security'
$PolicyKeyPath          = 'SOFTWARE\Policies\Microsoft\Windows\EventLog\Security'
$CrashOnAuditFailKey    = 'SYSTEM\CurrentControlSet\Control\Lsa'
$ClearLog               = $false
$RecoverCrashOnAuditFail = $true

$PackageName = 'SecurityLogFull'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-RegistryValue { param([string]$Path, [string]$Name)
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path)
    if ($null -eq $key) { return $null }
    try {
        $value = $key.GetValue($Name, $null)
        if ($null -eq $value) { return $null }
        return $value
    }
    finally { $key.Dispose() }
}

function Set-CrashOnAuditFail { param([int]$Value)
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($CrashOnAuditFailKey, $true)
    if ($null -eq $key) { throw 'Lsa registry key is not accessible.' }
    try { $key.SetValue('CrashOnAuditFail', $Value, [Microsoft.Win32.RegistryValueKind]::DWord) }
    finally { $key.Dispose() }
}

function Test-RetentionPolicy {
    $value = Get-RegistryValue -Path $PolicyKeyPath -Name 'Retention'
    if ($null -eq $value) { return $false }
    return ([string]$value -eq '1')
}

function Get-SecurityLogState {
    $configuration = $null
    try {
        $configuration = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($LogName)
        $info = [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetLogInformation($LogName, [System.Diagnostics.Eventing.Reader.PathType]::LogName)
        $maxBytes = [int64]$configuration.MaximumSizeInBytes
        $fileBytes = [int64]$info.FileSize
        $percent = 0
        if ($maxBytes -gt 0) { $percent = [int]([math]::Round(($fileBytes * 100.0) / $maxBytes)) }
        if ($percent -gt 100) { $percent = 100 }
        return [pscustomobject]@{
            Mode        = [string]$configuration.LogMode
            MaxBytes    = $maxBytes
            UsedPercent = $percent
            IsFull      = [bool]$info.IsLogFull
            Records     = [int64]$info.RecordCount
        }
    }
    finally {
        if ($null -ne $configuration) { $configuration.Dispose() }
    }
}

try {
    $logs = @([System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetLogNames())
    if ($logs -notcontains $LogName) { Exit-Script 0 "NotApplicable | Log=$LogName; Reason=ChannelMissing" }

    $state = Get-SecurityLogState
    $policyManaged = Test-RetentionPolicy
    $crashValue = Get-RegistryValue -Path $CrashOnAuditFailKey -Name 'CrashOnAuditFail'
    $crashBefore = 'Unknown'
    if ($null -ne $crashValue) { $crashBefore = [string]$crashValue }
    $maxMB = [int]([math]::Round($state.MaxBytes / 1MB))

    if ($state.Mode -ne 'Retain' -and $crashBefore -ne '2') {
        Exit-Script 0 "Healthy | Log=$LogName; Mode=$($state.Mode); UsedPercent=$($state.UsedPercent); MaxMB=$maxMB; CrashOnAuditFail=$crashBefore"
    }

    if ($state.Mode -eq 'Retain' -and $policyManaged) {
        Exit-Script 1 "Failed | Log=$LogName; Mode=Retain; PolicyRetention=True; Action=ChangeEventLogPolicy; CrashOnAuditFail=$crashBefore"
    }

    $modeBefore = $state.Mode
    $percentBefore = $state.UsedPercent
    $fullBefore = $state.IsFull
    $cleared = $false
    $recovered = $false

    if ($state.Mode -eq 'Retain') {
        $configuration = $null
        $verification = $null
        try {
            $configuration = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($LogName)
            $configuration.LogMode = [System.Diagnostics.Eventing.Reader.EventLogMode]::Circular
            $configuration.SaveChanges()
            Write-IRTLog "Log mode changed | Log=$LogName; Previous=Retain; Requested=Circular"
            $verification = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($LogName)
            if ([string]$verification.LogMode -ne 'Circular') { throw 'Log mode verification failed.' }
        }
        finally {
            if ($null -ne $verification) { $verification.Dispose() }
            if ($null -ne $configuration) { $configuration.Dispose() }
        }
    }

    if ($ClearLog -and $state.IsFull) {
        [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($LogName)
        $cleared = $true
        Write-IRTLog "Log cleared | Log=$LogName"
    }

    if ($crashBefore -eq '2' -and $RecoverCrashOnAuditFail) {
        Set-CrashOnAuditFail -Value 1
        $crashAfterWrite = Get-RegistryValue -Path $CrashOnAuditFailKey -Name 'CrashOnAuditFail'
        if ($null -eq $crashAfterWrite -or [string]$crashAfterWrite -ne '1') { throw 'CrashOnAuditFail verification failed.' }
        $recovered = $true
        Write-IRTLog "CrashOnAuditFail reset | Previous=2; Current=1"
    }

    $final = Get-SecurityLogState
    $crashAfter = Get-RegistryValue -Path $CrashOnAuditFailKey -Name 'CrashOnAuditFail'
    $crashAfterText = 'Unknown'
    if ($null -ne $crashAfter) { $crashAfterText = [string]$crashAfter }

    if ($final.Mode -eq 'Retain') {
        Exit-Script 1 "Failed | Log=$LogName; Mode=Retain; Verification=Failed; CrashOnAuditFail=$crashAfterText"
    }
    if ($crashBefore -eq '2' -and -not $RecoverCrashOnAuditFail) {
        Exit-Script 1 "Failed | Log=$LogName; Mode=$($final.Mode); CrashOnAuditFail=2; Recovery=Disabled"
    }
    if ($crashBefore -eq '2' -and $crashAfterText -eq '2') {
        Exit-Script 1 "Failed | Log=$LogName; Mode=$($final.Mode); CrashOnAuditFail=2; Verification=Failed"
    }

    Exit-Script 0 "Fixed | Log=$LogName; Mode=$modeBefore->$($final.Mode); FullBefore=$fullBefore; UsedPercentBefore=$percentBefore; MaxMB=$maxMB; Cleared=$cleared; Recovered=$recovered; CrashOnAuditFail=$crashBefore->$crashAfterText"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
