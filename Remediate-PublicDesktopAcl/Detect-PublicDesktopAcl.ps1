<#
.SYNOPSIS
  Detection script for delete rights on the Public Desktop folder.

.DESCRIPTION
  Reads the ACL of the Public Desktop folder and checks whether standard users can delete shortcuts that installers place there. Exits 1 if the delete rights are missing or denied, 0 if they are present.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$UserGroupSids = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')

$PackageName = 'PublicDesktopAcl'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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
function Resolve-IdentitySid { param($Identity)
    try { return $Identity.Translate([System.Security.Principal.SecurityIdentifier]).Value }
    catch { return [string]$Identity }
}
function Test-RightIncluded { param($Rights, $Wanted)
    return (($Rights -band $Wanted) -eq $Wanted)
}
function Get-PublicDesktopPath {
    $path = [Environment]::GetFolderPath('CommonDesktopDirectory')
    if ([string]::IsNullOrWhiteSpace($path)) { return '' }
    return $path
}
function Get-DeleteState { param([string]$Path)
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $folderDeleteChild = $false
    $childDelete = $false
    $denied = $false
    foreach ($rule in @($acl.Access)) {
        $sid = Resolve-IdentitySid $rule.IdentityReference
        if ($UserGroupSids -notcontains $sid) { continue }
        $rights = $rule.FileSystemRights
        if ($rule.AccessControlType -eq 'Deny') {
            if (Test-RightIncluded $rights ([System.Security.AccessControl.FileSystemRights]::Delete)) { $denied = $true }
            if (Test-RightIncluded $rights ([System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles)) { $denied = $true }
            continue
        }
        if (Test-RightIncluded $rights ([System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles)) { $folderDeleteChild = $true }
        if (Test-RightIncluded $rights ([System.Security.AccessControl.FileSystemRights]::Delete)) {
            if (($rule.InheritanceFlags -band [System.Security.AccessControl.InheritanceFlags]::ObjectInherit) -ne 0) { $childDelete = $true }
        }
    }
    return [pscustomobject]@{
        FolderDeleteChild = $folderDeleteChild
        ChildDelete       = $childDelete
        Denied            = $denied
    }
}

try {
    $folder = Get-PublicDesktopPath
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        Exit-Script 0 'NotApplicable | Reason=PublicDesktopNotFound'
    }

    $state = Get-DeleteState -Path $folder
    $items = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue)
    $common = 'Folder=PublicDesktop; DeleteChild={0}; ChildDelete={1}; Deny={2}; Items={3}' -f $state.FolderDeleteChild, $state.ChildDelete, $state.Denied, $items.Count

    if ($state.Denied) {
        Write-IRTLog 'A deny entry for the user groups blocks delete on the Public Desktop.' 'WARN'
        Exit-Script 1 "Drift | $common"
    }
    if ($state.FolderDeleteChild -and $state.ChildDelete) {
        Exit-Script 0 "Healthy | $common"
    }
    Exit-Script 1 "Drift | $common"
}
catch { Exit-Script 1 ('Error: Operation=None; HResult=0x{0:X8}' -f $_.Exception.HResult) }
