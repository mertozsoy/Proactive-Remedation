<#
.SYNOPSIS
  Remediation script for old zero-byte IME Incoming downloads.

.DESCRIPTION
  Deletes only unchanged old top-level GUID_version.bin files while holding a
  handle that denies read and write sharing. Verifies stale candidates are gone.
  Does not restart IME or force an application retry. Exits 1 if candidates remain.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeHours = 24
$ObservationSeconds = 30
$EnableRemediation = $true

$PackageName = 'StuckImeIncoming'
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
function Test-SafeIncoming { param([string]$Path)
    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer) { throw 'InvalidIncomingDirectory' }
    while ($null -ne $directory) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'ReparsePointRejected' }
        $directory = $directory.Parent
    }
}
function Get-StaleIncoming {
    Get-ChildItem -LiteralPath $IncomingPath -File -Force -ErrorAction Stop | Where-Object {
        $_.Name -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}_[0-9]+\.bin$' -and
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        $_.Length -eq 0 -and $_.CreationTimeUtc -lt $CutoffUtc -and $_.LastWriteTimeUtc -lt $CutoffUtc
    }
}
try {
    if ($MinimumAgeHours -lt 24 -or $ObservationSeconds -lt 10 -or $ObservationSeconds -gt 120) { throw 'InvalidThreshold' }
    $programFiles = ${env:ProgramFiles(x86)}
    if (-not $programFiles) { $programFiles = $env:ProgramFiles }
    $IncomingPath = Join-Path $programFiles 'Microsoft Intune Management Extension\Content\Incoming'
    if (-not (Test-Path -LiteralPath $IncomingPath -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | Incoming=Missing' }
    Test-SafeIncoming -Path $IncomingPath
    $CutoffUtc = [DateTime]::UtcNow.AddHours(-$MinimumAgeHours)
    $initial = @(Get-StaleIncoming)
    if ($initial.Count -eq 0) { Exit-Script 0 'Healthy | StaleZeroByte=0' }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | StaleZeroByte=$($initial.Count); Enabled=False" }
    Start-Sleep -Seconds $ObservationSeconds
    $removed = 0
    $deferred = 0
    foreach ($candidate in $initial) {
        $stream = $null
        try {
            Test-SafeIncoming -Path $IncomingPath
            $fresh = Get-Item -LiteralPath $candidate.FullName -Force -ErrorAction Stop
            if ($fresh.PSIsContainer -or ($fresh.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $deferred++; continue }
            if ($fresh.Length -ne 0 -or $fresh.CreationTimeUtc -ne $candidate.CreationTimeUtc -or
                $fresh.LastWriteTimeUtc -ne $candidate.LastWriteTimeUtc) { $deferred++; continue }
            $stream = [IO.File]::Open($fresh.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Delete)
            $fresh.Refresh()
            if ($stream.Length -ne 0 -or $fresh.CreationTimeUtc -ne $candidate.CreationTimeUtc -or
                $fresh.LastWriteTimeUtc -ne $candidate.LastWriteTimeUtc) { $deferred++; continue }
            [IO.File]::Delete($fresh.FullName)
            $stream.Dispose()
            $stream = $null
            if (Test-Path -LiteralPath $fresh.FullName -ErrorAction Stop) { $deferred++; continue }
            $removed++
        }
        catch {
            $deferred++
            Write-IRTLog "Deferred | Type=$($_.Exception.GetType().Name)" 'WARN'
        }
        finally { if ($null -ne $stream) { $stream.Dispose() } }
    }
    Test-SafeIncoming -Path $IncomingPath
    $remaining = @(Get-StaleIncoming)
    if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | Removed=$removed; Deferred=$deferred; Remaining=$($remaining.Count)" }
    Exit-Script 0 "Fixed | Removed=$removed; Deferred=$deferred; Remaining=0; Retry=IMEManaged"
}
catch { Exit-Script 1 "Error | Type=$($_.Exception.GetType().Name); Action=InspectIncoming" }
