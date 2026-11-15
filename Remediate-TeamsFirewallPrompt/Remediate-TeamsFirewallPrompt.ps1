<#
.SYNOPSIS
  Remediation script that stops the Windows Firewall query popup for Microsoft Teams on shared and meeting room PCs.

.DESCRIPTION
  Exports the local firewall policy, adds a machine wide inbound allow rule for every Microsoft Teams executable on the device and removes Query User block rules that point to Teams. Optionally turns off the Query User popup for all apps. Exits 0 if every Teams executable is covered, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RuleGroup             = 'Intune - Teams Shared PC Firewall'
$RuleProfiles          = 'Any'
$DisableQueryUserPopup = $false
$BackupFolder          = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'TeamsFirewallPrompt'
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

function Get-TeamsRule {
    $list = @()
    foreach ($rule in Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue) {
        $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if ($null -eq $appFilter) { continue }
        $list += [pscustomobject]@{
            Name     = [string]$rule.Name
            Program  = [string]$appFilter.Program
            Enabled  = [string]$rule.Enabled
            Direction= [string]$rule.Direction
            Action   = [string]$rule.Action
        }
    }
    $list
}

function Get-CoveredProgram {
    $covered = New-Object System.Collections.Generic.List[string]
    foreach ($rule in Get-TeamsRule) {
        if ($rule.Enabled -ne 'True') { continue }
        if ($rule.Direction -ne 'Inbound') { continue }
        if ($rule.Action -ne 'Allow') { continue }
        if ([string]::IsNullOrWhiteSpace($rule.Program)) { continue }
        $covered.Add($rule.Program)
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

function Get-TeamsKind { param([string]$Path)
    if ($Path -like '*\WindowsApps\*') { return 'NewTeams' }
    if ($Path -like '*\Users\*') { return 'ClassicPerUser' }
    'ClassicMachine'
}

function New-FirewallBackup {
    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -Path $BackupFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $target = Join-Path $BackupFolder ('FirewallPolicy-TeamsFirewallPrompt-{0}.wfw' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    & netsh.exe advfirewall export $target | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-IRTLog "Firewall export failed with exit code $LASTEXITCODE" 'WARN'
        return $false
    }
    Write-IRTLog 'Firewall policy exported'
    $true
}

try {
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    if (@($profiles | Where-Object { $_.AllowLocalFirewallRules -eq $false }).Count -gt 0) {
        Exit-Script 0 'NotApplicable | LocalFirewallRules=BlockedByPolicy'
    }

    $exes = @(Get-TeamsExecutable)
    if ($exes.Count -eq 0) { Exit-Script 0 'NotApplicable | TeamsExecutables=0' }

    $coverage = @(Get-CoveredProgram)
    $missing = @()
    foreach ($exe in $exes) {
        if ($coverage -notcontains $exe) { $missing += $exe }
    }

    $staleRules = @()
    foreach ($rule in Get-TeamsRule) {
        $healthy = ($exes -contains $rule.Program) -and $rule.Enabled -eq 'True' -and $rule.Direction -eq 'Inbound' -and $rule.Action -eq 'Allow'
        if (-not $healthy) { $staleRules += $rule }
    }

    $blockRules = @()
    foreach ($item in Get-QueryUserBlockRule) {
        if ($exes -contains $item.Program) { $blockRules += $item }
    }

    $popupNeeded = $false
    if ($DisableQueryUserPopup) {
        if (@($profiles | Where-Object { $_.NotifyOnListen -eq $true }).Count -gt 0) { $popupNeeded = $true }
    }

    if ($missing.Count -eq 0 -and $staleRules.Count -eq 0 -and $blockRules.Count -eq 0 -and -not $popupNeeded) {
        Exit-Script 0 "Healthy | TeamsExe=$($exes.Count); Covered=$($exes.Count); Missing=0"
    }

    New-FirewallBackup | Out-Null

    $staleRemoved = 0
    foreach ($rule in $staleRules) {
        Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
        Write-IRTLog "Stale rule removed ($(Get-TeamsKind -Path $rule.Program))"
        $staleRemoved++
    }

    $blockRemoved = 0
    foreach ($item in $blockRules) {
        try {
            Remove-NetFirewallRule -Name $item.Name -ErrorAction Stop
            Write-IRTLog "Query User block rule removed ($(Get-TeamsKind -Path $item.Program))"
            $blockRemoved++
        }
        catch { Write-IRTLog "Block rule not removed: $($_.Exception.Message)" 'WARN' }
    }

    $added = 0
    foreach ($exe in $missing) {
        $kind = Get-TeamsKind -Path $exe
        $ruleName = 'IRT-TeamsSharedPC-{0}' -f ([guid]::NewGuid().ToString())
        New-NetFirewallRule -Name $ruleName -DisplayName 'Teams Shared PC Inbound' `
            -Description 'Inbound allow rule for Microsoft Teams on shared and meeting room PCs.' `
            -Group $RuleGroup -Direction Inbound -Program $exe -Action Allow `
            -Profile $RuleProfiles -Enabled True -ErrorAction Stop | Out-Null
        Write-IRTLog "Allow rule added ($kind)"
        $added++
    }

    $popupState = 'On'
    if ($DisableQueryUserPopup) {
        Set-NetFirewallProfile -Profile Domain,Private,Public -NotifyOnListen False -ErrorAction Stop
        Write-IRTLog 'Query User popup disabled'
    }

    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    if (@($profiles | Where-Object { $_.NotifyOnListen -eq $true }).Count -eq 0) { $popupState = 'Off' }

    $coverage = @(Get-CoveredProgram)
    $left = @()
    foreach ($exe in $exes) {
        if ($coverage -notcontains $exe) { $left += $exe }
    }
    $leftBlock = 0
    foreach ($item in Get-QueryUserBlockRule) {
        if ($exes -contains $item.Program) { $leftBlock++ }
    }

    $summary = 'Added={0}; StaleRemoved={1}; QueryBlockRemoved={2}; TeamsExe={3}; Covered={4}; Popup={5}' -f $added, $staleRemoved, $blockRemoved, $exes.Count, ($exes.Count - $left.Count), $popupState
    if ($left.Count -gt 0 -or $leftBlock -gt 0) { Exit-Script 1 "Failed | $summary; Remaining=$($left.Count); RemainingBlock=$leftBlock" }
    if ($DisableQueryUserPopup -and $popupState -ne 'Off') { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 ('Error: ' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
