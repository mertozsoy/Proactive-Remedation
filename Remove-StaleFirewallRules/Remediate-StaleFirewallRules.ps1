<#
.SYNOPSIS
  Remediation script that removes orphaned and user created local firewall allow rules.

.DESCRIPTION
  Reads local firewall rules from the persistent store, exports the local rule registry key and removes allow rules whose program or service no longer exists. Rules under user writable folders are removed only when the matching toggle is enabled. Policy rules are never touched. Exits 0 when no targeted rule is left, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RemoveOrphanedRules    = $true
$RemoveUserCreatedRules = $false
$KeepRuleNames          = @()
$KeepProgramPaths       = @()
$UserWritableRoots      = @("$env:SystemDrive\Users", "$env:SystemDrive\Windows\Temp")
$MaxItemsInOutput       = 6
$BackupRoot             = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
$RuleRegistryKey        = 'HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules'

$PackageName = 'StaleFirewallRules'
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

function Test-PathUnder { param([string]$Path, [string[]]$Roots)
    foreach ($root in $Roots) {
        if (-not $root) { continue }
        $rootFull = $root.TrimEnd('\')
        if ($Path.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($Path.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-KeptProgram { param([string]$Program)
    if (-not $Program) { return $false }
    foreach ($kept in $KeepProgramPaths) {
        if (-not $kept) { continue }
        if ($Program.Equals($kept, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-ServiceExists { param([string]$Service)
    return (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Service")
}

function Get-RuleLabel { param([string]$Program, [string]$Service)
    if ($Program) {
        try { return (Split-Path -Leaf $Program) } catch { return 'program' }
    }
    if ($Service) { return $Service }
    return 'rule'
}

function Get-LocalAllowRule {
    $found = @()
    $rules = @(Get-NetFirewallRule -PolicyStore PersistentStore -Action Allow -ErrorAction Stop)
    foreach ($rule in $rules) {
        $name    = [string]$rule.Name
        $display = [string]$rule.DisplayName
        $group   = [string]$rule.Group
        if ($group -and ($group -like '@*' -or $group -like 'Intune*')) { continue }
        if ($KeepRuleNames -contains $name -or $KeepRuleNames -contains $display) { continue }

        $program = ''
        $app = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if ($app) { $program = ([string]$app.Program).Trim('"') }
        if ($program -eq 'Any' -or $program -eq 'System') { $program = '' }
        if ($program) {
            try { $program = [Environment]::ExpandEnvironmentVariables($program) } catch { }
        }
        if (Test-KeptProgram -Program $program) { continue }

        $service = ''
        $serviceFilter = $rule | Get-NetFirewallServiceFilter -ErrorAction SilentlyContinue
        if ($serviceFilter) { $service = [string]$serviceFilter.Service }
        if ($service -eq 'Any') { $service = '' }

        $wildcard = $false
        if ($program -and $program.Contains('*')) { $wildcard = $true }

        $kind = ''
        if ($program -and -not $wildcard -and -not (Test-Path -LiteralPath $program)) {
            $kind = 'Orphan'
        }
        elseif (-not $program -and $service -and -not (Test-ServiceExists -Service $service)) {
            $kind = 'Orphan'
        }
        elseif (([string]$rule.Direction) -eq 'Inbound' -and ([string]$rule.Enabled) -eq 'True' -and -not $group -and $program -and -not $wildcard -and (Test-PathUnder -Path $program -Roots $UserWritableRoots)) {
            $kind = 'UserApp'
        }
        if (-not $kind) { continue }

        $found += [pscustomobject]@{
            Name        = $name
            DisplayName = $display
            Kind        = $kind
            Label       = (Get-RuleLabel -Program $program -Service $service)
        }
    }
    $found
}

function Save-FirewallBackup {
    $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    $file = Join-Path $BackupRoot ('FirewallLocalRules-{0}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $output = & reg.exe export $RuleRegistryKey $file /y 2>&1
    if ($LASTEXITCODE -ne 0) { throw "reg export failed with exit code $LASTEXITCODE ($($output -join ' '))" }
    return $file
}

try {
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    $merged   = @($profiles | Where-Object { $_.AllowLocalFirewallRules -ne $false })
    if ($merged.Count -eq 0) { Exit-Script 0 'NotApplicable | LocalFirewallRules=BlockedByPolicy' }

    $allAllow = @(Get-NetFirewallRule -PolicyStore PersistentStore -Action Allow -ErrorAction Stop)
    $items    = @(Get-LocalAllowRule)
    $orphan   = @($items | Where-Object { $_.Kind -eq 'Orphan' })
    $user     = @($items | Where-Object { $_.Kind -eq 'UserApp' })

    if ($items.Count -eq 0) { Exit-Script 0 "Healthy | LocalAllow=$($allAllow.Count); Orphaned=0; UserApp=0" }

    $targets = @($items | Where-Object {
        ($_.Kind -eq 'Orphan' -and $RemoveOrphanedRules) -or ($_.Kind -eq 'UserApp' -and $RemoveUserCreatedRules)
    })

    $labels = @($items | Select-Object -First $MaxItemsInOutput | ForEach-Object { '{0}:{1}' -f $_.Kind, $_.Label })
    if ($targets.Count -eq 0) {
        Exit-Script 1 "ReportOnly | Orphaned=$($orphan.Count); UserApp=$($user.Count); Items=$($labels -join ', '); Toggle=RemoveUserCreatedRules"
    }

    $backupFile = Save-FirewallBackup
    Write-IRTLog "Backup written to $backupFile"

    $removedOrphan = 0
    $removedUser   = 0
    $failed        = 0
    foreach ($rule in $targets) {
        try {
            Remove-NetFirewallRule -Name $rule.Name -PolicyStore PersistentStore -ErrorAction Stop
            if ($rule.Kind -eq 'Orphan') { $removedOrphan++ } else { $removedUser++ }
            Write-IRTLog "Rule removed ($($rule.Kind)): $($rule.DisplayName)"
        }
        catch {
            $failed++
            Write-IRTLog "Rule not removed ($($rule.Kind)): $($_.Exception.Message)" 'WARN'
        }
    }

    $remaining = @(Get-LocalAllowRule)
    $leftOrphan = @($remaining | Where-Object { $_.Kind -eq 'Orphan' }).Count
    $leftUser   = @($remaining | Where-Object { $_.Kind -eq 'UserApp' }).Count
    $removed    = $removedOrphan + $removedUser

    if ($remaining.Count -eq 0) {
        Exit-Script 0 "Fixed | Removed=$removed; Orphaned=$removedOrphan; UserApp=$removedUser; Backup=$backupFile"
    }
    if ($leftOrphan -eq 0 -and -not $RemoveUserCreatedRules) {
        Exit-Script 1 "ReportOnly | Removed=$removed; RemainingUserApp=$leftUser; Toggle=RemoveUserCreatedRules; Backup=$backupFile"
    }
    Exit-Script 1 "Failed | Removed=$removed; RemainingOrphaned=$leftOrphan; RemainingUserApp=$leftUser; Failed=$failed; Backup=$backupFile"
}
catch { Exit-Script 1 ('Error: ' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
