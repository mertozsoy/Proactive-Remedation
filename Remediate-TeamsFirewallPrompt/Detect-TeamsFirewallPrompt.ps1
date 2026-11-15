<#
.SYNOPSIS
  Detection script for the Windows Firewall query popup that Microsoft Teams shows on shared and meeting room PCs.

.DESCRIPTION
  Finds every Microsoft Teams executable on the device and checks whether an enabled inbound allow rule exists for it. Also finds auto generated Query User block rules that keep dropping inbound traffic to Teams. Exits 1 if a rule is missing or a block rule is present, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RuleGroup             = 'Intune - Teams Shared PC Firewall'
$DisableQueryUserPopup = $false

$PackageName = 'TeamsFirewallPrompt'
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

function Get-TeamsExecutable {
    $list = New-Object System.Collections.Generic.List[string]

    $machinePaths = @()
    if ($env:ProgramFiles) { $machinePaths += (Join-Path $env:ProgramFiles 'Teams\current\Teams.exe') }
    $x86Root = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($x86Root) { $machinePaths += (Join-Path $x86Root 'Teams\current\Teams.exe') }
    foreach ($path in $machinePaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { $list.Add($path) }
    }

    if ($env:ProgramFiles) {
        $appRoot = Join-Path $env:ProgramFiles 'WindowsApps'
        if (Test-Path -LiteralPath $appRoot) {
            foreach ($dir in Get-ChildItem -LiteralPath $appRoot -Directory -Filter 'MSTeams_*' -ErrorAction SilentlyContinue) {
                $exe = Join-Path $dir.FullName 'ms-teams.exe'
                if (Test-Path -LiteralPath $exe -PathType Leaf) { $list.Add($exe) }
            }
        }
    }

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        foreach ($userDir in Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue) {
            $exe = Join-Path $userDir.FullName 'AppData\Local\Microsoft\Teams\current\Teams.exe'
            if (Test-Path -LiteralPath $exe -PathType Leaf) { $list.Add($exe) }
        }
    }

    @($list | Sort-Object -Unique)
}

function Get-CoveredProgram {
    $covered = New-Object System.Collections.Generic.List[string]
    foreach ($rule in Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue) {
        if ($rule.Enabled -ne 'True') { continue }
        if ($rule.Direction -ne 'Inbound') { continue }
        if ($rule.Action -ne 'Allow') { continue }
        $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if ($null -eq $appFilter) { continue }
        if ([string]::IsNullOrWhiteSpace($appFilter.Program)) { continue }
        $covered.Add([string]$appFilter.Program)
    }
    $covered
}

function Get-QueryUserBlockRule {
    $found = @()
    foreach ($rule in Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue) {
        $ruleName = [string]$rule.Name
        $ruleDisplay = [string]$rule.DisplayName
        if ($ruleName -notlike '*Query User*' -and $ruleDisplay -notlike '*Query User*') { continue }
        $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if ($null -eq $appFilter) { continue }
        if ([string]::IsNullOrWhiteSpace($appFilter.Program)) { continue }
        $found += [pscustomobject]@{ Name = $ruleName; Program = [string]$appFilter.Program }
    }
    $found
}

try {
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    if (@($profiles | Where-Object { $_.AllowLocalFirewallRules -eq $false }).Count -gt 0) {
        Exit-Script 0 'NotApplicable | LocalFirewallRules=BlockedByPolicy'
    }

    $exes = @(Get-TeamsExecutable)
    if ($exes.Count -eq 0) { Exit-Script 0 'NotApplicable | TeamsExecutables=0' }

    $covered = @(Get-CoveredProgram)
    $missing = @()
    foreach ($exe in $exes) {
        if ($covered -notcontains $exe) { $missing += $exe }
    }

    $queryBlock = 0
    foreach ($item in Get-QueryUserBlockRule) {
        if ($exes -contains $item.Program) { $queryBlock++ }
    }

    $popupState = 'On'
    if (@($profiles | Where-Object { $_.NotifyOnListen -eq $true }).Count -eq 0) { $popupState = 'Off' }

    $summary = 'TeamsExe={0}; Covered={1}; Missing={2}; QueryBlock={3}; Popup={4}' -f $exes.Count, ($exes.Count - $missing.Count), $missing.Count, $queryBlock, $popupState
    if ($missing.Count -gt 0 -or $queryBlock -gt 0) { Exit-Script 1 "Drift | $summary" }
    if ($DisableQueryUserPopup -and $popupState -ne 'Off') { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error: ' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
