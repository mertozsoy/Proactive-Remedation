<#
.SYNOPSIS
  Detection script for missing or broken Office and Edge Start menu shortcuts.

.DESCRIPTION
  Resolves the Office and Edge executables, scans the all users and per user Start menu program folders and checks every shortcut that points to those executables. Exits 1 when an app has no working shortcut or a dead copy, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetApps = @(
    @{ Name = 'Word'; Title = 'Word'; Exe = 'WINWORD.EXE' },
    @{ Name = 'Excel'; Title = 'Excel'; Exe = 'EXCEL.EXE' },
    @{ Name = 'Outlook'; Title = 'Outlook'; Exe = 'OUTLOOK.EXE' },
    @{ Name = 'PowerPoint'; Title = 'PowerPoint'; Exe = 'POWERPNT.EXE' },
    @{ Name = 'Edge'; Title = 'Microsoft Edge'; Exe = 'MSEDGE.EXE' }
)
$HealthyStates = @('Healthy', 'Advertised')

$PackageName = 'OfficeEdgeShortcuts'
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

function Resolve-AppExecutable {
    param([string]$ExeName)
    $candidates = @()
    foreach ($key in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExeName", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$ExeName")) {
        $value = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).'(default)'
        if ($value) { $candidates += ([string]$value).Trim().Trim('"') }
    }
    $officeRoots = @()
    if ($env:ProgramFiles) { $officeRoots += (Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16') }
    if (${env:ProgramFiles(x86)}) { $officeRoots += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\root\Office16') }
    foreach ($root in $officeRoots) { $candidates += (Join-Path $root $ExeName) }
    $edgeRoots = @()
    if (${env:ProgramFiles(x86)}) { $edgeRoots += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application') }
    if ($env:ProgramFiles) { $edgeRoots += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application') }
    foreach ($root in $edgeRoots) { $candidates += (Join-Path $root $ExeName) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-StartMenuRoot {
    $roots = @()
    $common = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    if (Test-Path -LiteralPath $common -PathType Container) { $roots += [pscustomobject]@{ Scope = 'AllUsers'; Path = $common } }
    $skipped = @('systemprofile', 'localservice', 'networkservice', 'default', 'default user', 'public', 'all users')
    foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue)) {
        $imagePath = (Get-ItemProperty -LiteralPath $key.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $imagePath) { continue }
        $imagePath = [Environment]::ExpandEnvironmentVariables([string]$imagePath)
        $leaf = (Split-Path -Leaf $imagePath).ToLowerInvariant()
        if ($skipped -contains $leaf) { continue }
        $programs = Join-Path $imagePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
        if (Test-Path -LiteralPath $programs -PathType Container) { $roots += [pscustomobject]@{ Scope = 'User'; Path = $programs } }
    }
    return $roots
}

function Get-ShortcutEntry {
    param($Shell, $Roots)
    $entries = @()
    foreach ($root in $Roots) {
        foreach ($file in @(Get-ChildItem -LiteralPath $root.Path -Filter '*.lnk' -Recurse -Force -ErrorAction SilentlyContinue)) {
            $state = 'Healthy'
            $targetLeaf = ''
            $iconPath = ''
            if ($file.Length -eq 0) { $state = 'EmptyShortcut' }
            else {
                $link = $null
                try { $link = $Shell.CreateShortcut($file.FullName) } catch { $link = $null }
                if (-not $link) { $state = 'Unreadable' }
                else {
                    if ($link.IconLocation) { $iconPath = [Environment]::ExpandEnvironmentVariables((($link.IconLocation -split ',')[0]).Trim().Trim('"')) }
                    if ($link.TargetPath) {
                        $targetLeaf = (Split-Path -Leaf $link.TargetPath).ToUpperInvariant()
                        if (-not (Test-Path -LiteralPath $link.TargetPath -PathType Leaf)) { $state = 'TargetMissing' }
                        elseif ($iconPath -and -not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { $state = 'IconMissing' }
                    }
                    elseif ($iconPath -and (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
                        $targetLeaf = (Split-Path -Leaf $iconPath).ToUpperInvariant()
                        $state = 'Advertised'
                    }
                    else { $state = 'NoTarget' }
                }
            }
            $entries += [pscustomobject]@{ Scope = $root.Scope; Root = $root.Path; Path = $file.FullName; State = $state; TargetLeaf = $targetLeaf }
        }
    }
    return $entries
}

function Get-AppState {
    param([string]$ExeName, $Entries, $Roots)
    $found = @($Entries | Where-Object { $_.TargetLeaf -eq $ExeName })
    if ($found.Count -eq 0) { return 'Missing' }
    $healthy = @($found | Where-Object { $HealthyStates -contains $_.State })
    $broken = @($found | Where-Object { $HealthyStates -notcontains $_.State })
    if ($healthy.Count -eq 0) { return 'Broken' }
    if ($broken.Count -gt 0) { return 'Duplicate' }
    if (@($healthy | Where-Object { $_.Scope -eq 'AllUsers' }).Count -gt 0) { return 'OK' }
    foreach ($root in @($Roots | Where-Object { $_.Scope -eq 'User' })) {
        if (@($healthy | Where-Object { $_.Root -eq $root.Path }).Count -eq 0) { return 'Partial' }
    }
    return 'OK'
}

try {
    $shell = New-Object -ComObject WScript.Shell
    $roots = @(Get-StartMenuRoot)
    if ($roots.Count -eq 0) { Exit-Script 0 'NotApplicable | NoStartMenuFolders' }

    $entries = @(Get-ShortcutEntry -Shell $shell -Roots $roots)
    $states = @()
    foreach ($app in $TargetApps) {
        if (-not (Resolve-AppExecutable -ExeName $app.Exe)) { $states += ('{0}=NotInstalled' -f $app.Name); continue }
        $states += ('{0}={1}' -f $app.Name, (Get-AppState -ExeName $app.Exe -Entries $entries -Roots $roots))
    }
    $summary = $states -join '; '
    $faults = @($states | Where-Object { $_ -notmatch '=(OK|NotInstalled)$' })
    if ($faults.Count -gt 0) { Exit-Script 1 "Drift | $summary; Profiles=$(@($roots | Where-Object { $_.Scope -eq 'User' }).Count)" }
    Exit-Script 0 "Healthy | $summary; Profiles=$(@($roots | Where-Object { $_.Scope -eq 'User' }).Count)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
