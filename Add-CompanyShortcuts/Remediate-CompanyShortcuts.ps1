<#
.SYNOPSIS
  Remediation script for standard company shortcuts.

.DESCRIPTION
  Creates the missing or changed shortcuts from the list on the Desktop or Start menu of the signed-in user. Exits 0 if every applicable shortcut is in place, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$Shortcuts = @(
    @{ Name = 'Company Portal'; Target = 'explorer.exe'; Arguments = 'shell:AppsFolder\Microsoft.CompanyPortal_8wekyb3d8bbwe!App'; Location = 'Desktop'; Icon = ''; RequiresAppx = 'Microsoft.CompanyPortal' }
    @{ Name = 'Intranet'; Target = 'https://intranet.contoso.com'; Arguments = ''; Location = 'Desktop'; Icon = ''; RequiresAppx = '' }
)

$PackageName = 'CompanyShortcuts'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-ShortcutPlan {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($entry in $Shortcuts) {
        $isUrl  = $entry.Target -match '^https?://'
        $folder = [Environment]::GetFolderPath($(if ($entry.Location -eq 'StartMenu') { 'Programs' } else { 'Desktop' }))
        $path   = Join-Path $folder ($entry.Name + $(if ($isUrl) { '.url' } else { '.lnk' }))
        $state  = 'OK'

        if ($entry.RequiresAppx -and -not (Get-AppxPackage -Name $entry.RequiresAppx -ErrorAction SilentlyContinue)) { $state = 'Skipped' }
        elseif (-not $isUrl -and $entry.Target -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $entry.Target)) { $state = 'Skipped' }
        elseif (-not (Test-Path -LiteralPath $path)) { $state = 'Missing' }
        elseif ($isUrl) {
            $current = (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | Where-Object { $_ -like 'URL=*' } | Select-Object -First 1) -replace '^URL=', ''
            if ($current -ne $entry.Target) { $state = 'Changed' }
        }
        else {
            $link = $shell.CreateShortcut($path)
            if ($link.Arguments -ne $entry.Arguments -or ($entry.Target -match '\\' -and $link.TargetPath -ne $entry.Target)) { $state = 'Changed' }
        }
        [pscustomobject]@{ Name = $entry.Name; Path = $path; IsUrl = $isUrl; State = $state; Entry = $entry }
    }
}

try {
    if (-not $Shortcuts -or $Shortcuts.Count -eq 0) { Exit-Script 0 'NotApplicable | Shortcuts=None' }

    $shell   = New-Object -ComObject WScript.Shell
    $created = @()
    foreach ($item in @(Get-ShortcutPlan | Where-Object { $_.State -in 'Missing', 'Changed' })) {
        $entry = $item.Entry
        $icon  = if ($entry.Icon -and (Test-Path -LiteralPath $entry.Icon)) { $entry.Icon } else { '' }
        if ($item.IsUrl) {
            $lines = @('[InternetShortcut]', "URL=$($entry.Target)")
            if ($icon) { $lines += "IconFile=$icon", 'IconIndex=0' }
            Set-Content -LiteralPath $item.Path -Value $lines -Encoding ASCII -Force -ErrorAction Stop
        }
        else {
            $link = $shell.CreateShortcut($item.Path)
            $link.TargetPath = $entry.Target
            $link.Arguments  = $entry.Arguments
            if ($icon) { $link.IconLocation = "$icon,0" }
            $link.Save()
        }
        $created += $item.Name
        Write-IRTLog "Created $($item.Path)"
    }

    $plan    = @(Get-ShortcutPlan)
    $left    = @($plan | Where-Object { $_.State -in 'Missing', 'Changed' })
    $skipped = @($plan | Where-Object { $_.State -eq 'Skipped' })
    $summary = 'Created={0}; Skipped={1}' -f ($(if ($created) { $created -join ',' } else { 'None' })), ($(if ($skipped) { $skipped.Name -join ',' } else { 'None' }))

    if ($left.Count -eq 0) { Exit-Script 0 "Remediated | $summary" }
    Exit-Script 1 "Failed ($($left.Name -join ',')) | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
