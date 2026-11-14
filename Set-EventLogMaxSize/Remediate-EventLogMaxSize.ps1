<#
.SYNOPSIS
  Remediation script that increases undersized event log maximum sizes.

.DESCRIPTION
  Raises the configured size using EventLogConfiguration.SaveChanges and checks
  a fresh configuration object. Never shrinks or clears logs, enables channels,
  changes retention or restarts services. Conflicting Security policy values
  and explicitly excluded channels are not overwritten. Exits 1 on unresolved
  conflicts or failures and 0 after successful verification.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumLogSizesMB = [ordered]@{
    'Security' = 256
    'Microsoft-Windows-AppLocker/EXE and DLL' = 64
    'Microsoft-Windows-AppLocker/MSI and Script' = 64
    'Microsoft-Windows-AppLocker/Packaged app-Deployment' = 64
    'Microsoft-Windows-AppLocker/Packaged app-Execution' = 64
    'Microsoft-Windows-PowerShell/Operational' = 128
}
$ExternallyManagedLogs = @()

$PackageName = 'EventLogMaxSize'
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
function Get-RequiredLogSize { param([string]$Name, [long]$MinimumBytes)
    if ($Name -ne 'Security') { return $MinimumBytes }
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Policies\Microsoft\Windows\EventLog\Security')
    if ($null -eq $key) { return $MinimumBytes }
    try {
        $value = $key.GetValue('MaxSize', $null)
        if ($null -eq $value) { return $MinimumBytes }
        if ($key.GetValueKind('MaxSize') -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
            throw 'Security MaxSize policy has an unexpected type.'
        }
        $policyBytes = [long]$value * 1KB
        if ($policyBytes -lt 20MB -or $policyBytes -gt ([long]2147483647 * 1KB)) {
            throw 'Security MaxSize policy is outside the documented range.'
        }
        if ($policyBytes -lt $MinimumBytes) { return [long]-1 }
        return [long]([math]::Ceiling($policyBytes / 65536.0) * 65536)
    }
    finally { $key.Dispose() }
}

try {
    $availableLogs = @([System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.GetLogNames())
    $checked = 0
    $fixed = 0
    $missing = 0
    $excluded = 0
    $blocked = 0
    $failed = 0
    foreach ($name in $MinimumLogSizesMB.Keys) {
        $minimum = [long]$MinimumLogSizesMB[$name] * 1MB
        if ($minimum -lt 1MB -or $minimum -gt 4GB -or ($minimum % 65536) -ne 0) {
            throw 'Minimum sizes must be whole MB values between 1 and 4096.'
        }
        if ($name -eq 'Security' -and $minimum -lt 20MB) { throw 'Security requires at least 20 MB.' }
        if ($ExternallyManagedLogs -contains $name) {
            $excluded++
            Write-IRTLog "Excluded | Channel=$name; Reason=ExternalManagement"
            continue
        }
        if ($availableLogs -notcontains $name) {
            $missing++
            if ($name -eq 'Security') { $failed++ }
            Write-IRTLog "Missing | Channel=$name"
            continue
        }
        $configuration = $null
        $verification = $null
        try {
            $required = Get-RequiredLogSize -Name $name -MinimumBytes $minimum
            $configuration = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($name)
            $checked++
            if ($required -eq -1) {
                $blocked++
                Write-IRTLog "PolicyConflict | Channel=$name; MinimumBytes=$minimum"
                continue
            }
            $before = $configuration.MaximumSizeInBytes
            if ($before -ge $required) {
                Write-IRTLog "Healthy | Channel=$name; CurrentBytes=$before; RequiredBytes=$required"
                continue
            }
            $enabledBefore = $configuration.IsEnabled
            $modeBefore = $configuration.LogMode
            Write-IRTLog "Changing | Channel=$name; PreviousBytes=$before; RequiredBytes=$required"
            $configuration.MaximumSizeInBytes = $required
            $configuration.SaveChanges()
            $verification = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($name)
            if ($verification.MaximumSizeInBytes -lt $required -or $verification.IsEnabled -ne $enabledBefore -or $verification.LogMode -ne $modeBefore) {
                throw 'Event log configuration verification failed.'
            }
            $fixed++
            Write-IRTLog "Fixed | Channel=$name; PreviousBytes=$before; CurrentBytes=$($verification.MaximumSizeInBytes)"
        }
        catch {
            $failed++
            Write-IRTLog "ChangeFailed | Channel=$name; Exception=$($_.Exception.GetType().Name)" 'ERROR'
        }
        finally {
            if ($null -ne $verification) { $verification.Dispose() }
            if ($null -ne $configuration) { $configuration.Dispose() }
        }
    }
    $summary = "Checked=$checked; Fixed=$fixed; PolicyBlocked=$blocked; Missing=$missing; Excluded=$excluded; Failed=$failed"
    if (($blocked + $failed) -gt 0) { Exit-Script 1 "Failed | $summary" }
    if ($checked -eq 0) { Exit-Script 0 "NotApplicable | $summary" }
    if ($fixed -eq 0) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: Operation=RemediateEventLogMaxSize; Exception=$($_.Exception.GetType().Name)" }
