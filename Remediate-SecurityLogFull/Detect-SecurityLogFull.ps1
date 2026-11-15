<#
.SYNOPSIS
  Detection script for a Security event log that cannot overwrite old events.

.DESCRIPTION
  Reads the Security channel mode, size and fill level and the CrashOnAuditFail
  value. Exits 1 if the channel is set to Retain or CrashOnAuditFail is 2.
  Exits 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$LogName             = 'Security'
$PolicyKeyPath       = 'SOFTWARE\Policies\Microsoft\Windows\EventLog\Security'
$CrashOnAuditFailKey = 'SYSTEM\CurrentControlSet\Control\Lsa'

$PackageName = 'SecurityLogFull'
$Phase       = 'Detect'
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
            FileBytes   = $fileBytes
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
    $crashText = 'Unknown'
    if ($null -ne $crashValue) { $crashText = [string]$crashValue }

    $maxMB = [int]([math]::Round($state.MaxBytes / 1MB))
    $details = "Log=$LogName; Mode=$($state.Mode); Full=$($state.IsFull); UsedPercent=$($state.UsedPercent); MaxMB=$maxMB; Records=$($state.Records); PolicyRetention=$policyManaged; CrashOnAuditFail=$crashText"

    if ($state.Mode -eq 'Retain') {
        if ($policyManaged) { Exit-Script 1 "Drift | $details; Source=Policy" }
        Exit-Script 1 "Drift | $details; Source=Local"
    }
    if ($crashText -eq '2') { Exit-Script 1 "Drift | $details; Source=CrashOnAuditFail" }

    Exit-Script 0 "Healthy | $details"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
