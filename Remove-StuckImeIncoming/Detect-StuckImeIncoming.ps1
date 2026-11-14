<#
.SYNOPSIS
  Detection script for old zero-byte IME Incoming downloads.

.DESCRIPTION
  Checks top-level GUID_version.bin files twice for unchanged zero length and age.
  Exits 1 if stale candidates exist, 0 otherwise. Age is a heuristic, not job state.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeHours = 24
$ObservationSeconds = 30

$PackageName = 'StuckImeIncoming'
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
    if ($initial.Count -eq 0) { Exit-Script 0 "Healthy | StaleZeroByte=0; MinAgeHours=$MinimumAgeHours" }
    Start-Sleep -Seconds $ObservationSeconds
    Test-SafeIncoming -Path $IncomingPath
    $current = @{}
    foreach ($file in @(Get-StaleIncoming)) { $current[$file.FullName] = $file }
    $stable = @($initial | Where-Object {
        $current.ContainsKey($_.FullName) -and
        $current[$_.FullName].CreationTimeUtc -eq $_.CreationTimeUtc -and
        $current[$_.FullName].LastWriteTimeUtc -eq $_.LastWriteTimeUtc
    })
    if ($stable.Count -gt 0) { Exit-Script 1 "Drift | StaleZeroByte=$($stable.Count); MinAgeHours=$MinimumAgeHours" }
    Exit-Script 0 "Healthy | StaleZeroByte=0; MinAgeHours=$MinimumAgeHours"
}
catch { Exit-Script 1 "Error | Type=$($_.Exception.GetType().Name); Action=InspectIncoming" }
