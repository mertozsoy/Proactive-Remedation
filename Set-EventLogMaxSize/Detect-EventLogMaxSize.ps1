<#
.SYNOPSIS
  Detection script for undersized Security, AppLocker and PowerShell event logs.

.DESCRIPTION
  Reads configured maximum sizes, not current file lengths. Uses minimum limits
  and honors the Security MaxSize policy. Exits 1 for drift, policy conflicts or
  read errors. Exits 0 for healthy or explicitly excluded channels.

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
$Phase = 'Detect'
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
    $missing = 0
    $excluded = 0
    $drift = 0
    $blocked = 0
    $errors = 0
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
            if ($name -eq 'Security') { $errors++ }
            Write-IRTLog "Missing | Channel=$name"
            continue
        }
        $configuration = $null
        try {
            $required = Get-RequiredLogSize -Name $name -MinimumBytes $minimum
            $configuration = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($name)
            $checked++
            if ($required -eq -1) {
                $blocked++
                Write-IRTLog "PolicyConflict | Channel=$name; MinimumBytes=$minimum"
                continue
            }
            $current = $configuration.MaximumSizeInBytes
            if ($current -lt $required) { $drift++ }
            Write-IRTLog "Measured | Channel=$name; CurrentBytes=$current; RequiredBytes=$required; Enabled=$($configuration.IsEnabled)"
        }
        catch {
            $errors++
            Write-IRTLog "ReadFailed | Channel=$name; Exception=$($_.Exception.GetType().Name)" 'ERROR'
        }
        finally { if ($null -ne $configuration) { $configuration.Dispose() } }
    }
    $summary = "Checked=$checked; Drift=$drift; PolicyBlocked=$blocked; Missing=$missing; Excluded=$excluded; Errors=$errors"
    if (($drift + $blocked + $errors) -gt 0) { Exit-Script 1 "Drift | $summary" }
    if ($checked -eq 0) { Exit-Script 0 "NotApplicable | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Operation=DetectEventLogMaxSize; Exception=$($_.Exception.GetType().Name)" }
