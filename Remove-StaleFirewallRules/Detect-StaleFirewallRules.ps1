<#
.SYNOPSIS
  Detection script for local firewall allow rules that are orphaned or created by users.

.DESCRIPTION
  Reads local firewall rules from the persistent store and reports allow rules whose program or service no longer exists. It also reports inbound allow rules that point to a program under a user writable folder. Exits 1 if any such rule is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$KeepRuleNames     = @()
$KeepProgramPaths  = @()
$UserWritableRoots = @("$env:SystemDrive\Users", "$env:SystemDrive\Windows\Temp")
$MaxItemsInOutput  = 6

$PackageName = 'StaleFirewallRules'
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

try {
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    $merged   = @($profiles | Where-Object { $_.AllowLocalFirewallRules -ne $false })
    if ($merged.Count -eq 0) { Exit-Script 0 'NotApplicable | LocalFirewallRules=BlockedByPolicy' }

    $allAllow = @(Get-NetFirewallRule -PolicyStore PersistentStore -Action Allow -ErrorAction Stop)
    $items    = @(Get-LocalAllowRule)
    $orphan   = @($items | Where-Object { $_.Kind -eq 'Orphan' })
    $user     = @($items | Where-Object { $_.Kind -eq 'UserApp' })

    if ($items.Count -eq 0) { Exit-Script 0 "Healthy | LocalAllow=$($allAllow.Count); Orphaned=0; UserApp=0" }

    $labels = @($items | Select-Object -First $MaxItemsInOutput | ForEach-Object { '{0}:{1}' -f $_.Kind, $_.Label })
    $more   = ''
    if ($items.Count -gt $MaxItemsInOutput) { $more = '; More=' + ($items.Count - $MaxItemsInOutput) }
    Exit-Script 1 "Drift | Orphaned=$($orphan.Count); UserApp=$($user.Count); Items=$($labels -join ', ')$more"
}
catch { Exit-Script 1 ('Error: ' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
