<#
.SYNOPSIS
  Detection script for new Teams versions below an administrator-approved minimum.

.DESCRIPTION
  Reads MSTeams registrations for all users. Exits 1 for versions below the minimum or errors, 0 for healthy, inventory or not applicable states. Does not infer update age or query Defender.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumVersion = ''

$PackageName = 'NewTeams'
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

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error | Reason=Requires64BitPowerShell' }
    $minimum = $null
    if ($MinimumVersion) {
        if ($MinimumVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Exit-Script 1 'Error | Reason=InvalidMinimumVersion' }
        $minimum = [version]$MinimumVersion
    }
    $apps = @(Get-AppxPackage -AllUsers -Name 'MSTeams' -PackageTypeFilter Main -ErrorAction Stop)
    if ($apps.Count -eq 0) { Exit-Script 0 'NotApplicable | App=MSTeams; Registrations=0' }
    $versions = @($apps | ForEach-Object { [version]$_.Version } | Sort-Object -Unique)
    $oldest = $versions[0]
    $newest = $versions[-1]
    $details = "App=MSTeams; Versions=$($versions.Count); Oldest=$oldest; Newest=$newest"
    if ($null -eq $minimum) { Exit-Script 0 "Inventory | $details; Minimum=NotConfigured" }
    $below = @($apps | Where-Object { [version]$_.Version -lt $minimum }).Count
    if ($below -gt 0) { Exit-Script 1 "Drift | $details; Minimum=$minimum; BelowMinimum=$below" }
    Exit-Script 0 "Healthy | $details; Minimum=$minimum; BelowMinimum=0"
}
catch { Exit-Script 1 ('Error | Operation=TeamsInventory; HResult={0}' -f $_.Exception.HResult) }
