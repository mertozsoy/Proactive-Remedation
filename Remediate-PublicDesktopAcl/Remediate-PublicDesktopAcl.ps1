<#
.SYNOPSIS
  Remediation script that lets standard users delete shortcuts on the Public Desktop.

.DESCRIPTION
  Saves the current ACL of the Public Desktop folder, then grants the built-in Users group delete rights on the folder contents. Write access is not granted. Verifies the new ACL. Exits 0 when the delete rights are in place, 1 when blocked or incomplete.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$UserGroupSids             = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')
$UserGroupSid              = 'S-1-5-32-545'
$EnableRemediation         = $true
$GrantModifyInstead        = $false
$EnableShortcutInheritance = $false
$BackupRoot                = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'PublicDesktopAcl'
$Phase       = 'Remediate'
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
function Backup-FolderAcl { param([string]$Path)
    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        $null = New-Item -Path $BackupRoot -ItemType Directory -Force -ErrorAction Stop
    }
    $file = Join-Path $BackupRoot ('PublicDesktopAcl-{0}.acl' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    $output = & $icacls $Path /save $file /c 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) {
        throw "icacls /save failed with exit code $LASTEXITCODE ($($output -join ' '))"
    }
    return $file
}
function Add-DeleteGrant { param([string]$Path, [bool]$NeedFolder, [bool]$NeedChild)
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $sid = New-Object System.Security.Principal.SecurityIdentifier($UserGroupSid)
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $inheritChildren = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    if ($GrantModifyInstead) {
        $modifyRule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, [System.Security.AccessControl.FileSystemRights]::Modify, $inheritChildren, [System.Security.AccessControl.PropagationFlags]::None, $allow)
        $acl.AddAccessRule($modifyRule)
    }
    else {
        if ($NeedFolder) {
            $folderRule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles, [System.Security.AccessControl.InheritanceFlags]::None, [System.Security.AccessControl.PropagationFlags]::None, $allow)
            $acl.AddAccessRule($folderRule)
        }
        if ($NeedChild) {
            $childRule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, [System.Security.AccessControl.FileSystemRights]::Delete, $inheritChildren, [System.Security.AccessControl.PropagationFlags]::None, $allow)
            $acl.AddAccessRule($childRule)
        }
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Enable-ChildInheritance { param([string]$Path)
    $items = @(Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction Stop)
    $changed = 0
    $failed = 0
    foreach ($item in $items) {
        try {
            $acl = Get-Acl -LiteralPath $item.FullName -ErrorAction Stop
            if (-not $acl.AreAccessRulesProtected) { continue }
            $acl.SetAccessRuleProtection($false, $true)
            Set-Acl -LiteralPath $item.FullName -AclObject $acl -ErrorAction Stop
            $changed++
        }
        catch { $failed++ }
    }
    return [pscustomobject]@{ Changed = $changed; Failed = $failed }
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }

    $folder = Get-PublicDesktopPath
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        Exit-Script 0 'NotApplicable | Reason=PublicDesktopNotFound'
    }

    $state = Get-DeleteState -Path $folder
    $items = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue)
    $common = 'Folder=PublicDesktop; DeleteChild={0}; ChildDelete={1}; Deny={2}; Items={3}' -f $state.FolderDeleteChild, $state.ChildDelete, $state.Denied, $items.Count

    if ($state.FolderDeleteChild -and $state.ChildDelete -and -not $state.Denied) {
        Exit-Script 0 "Healthy | $common"
    }
    if ($state.Denied) {
        Exit-Script 1 "Blocked | Reason=DenyEntryPresent; $common; Changed=0"
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | $common; Changed=0"
    }

    $backup = Backup-FolderAcl -Path $folder
    Write-IRTLog "ACL saved: $backup"

    Add-DeleteGrant -Path $folder -NeedFolder (-not $state.FolderDeleteChild) -NeedChild (-not $state.ChildDelete)

    $inheritance = [pscustomobject]@{ Changed = 0; Failed = 0 }
    if ($EnableShortcutInheritance) {
        $inheritance = Enable-ChildInheritance -Path $folder
    }

    $after = Get-DeleteState -Path $folder
    $result = 'DeleteChild={0}; ChildDelete={1}; Items={2}; Backup={3}; AclReset={4}; AclFailed={5}' -f $after.FolderDeleteChild, $after.ChildDelete, $items.Count, $backup, $inheritance.Changed, $inheritance.Failed

    if ($after.FolderDeleteChild -and $after.ChildDelete -and -not $after.Denied) {
        Exit-Script 0 "Fixed | $result"
    }
    Exit-Script 1 "Failed | $result"
}
catch { Exit-Script 1 ('Error: Operation=AclUpdate; HResult=0x{0:X8}; Changed=Unknown' -f $_.Exception.HResult) }
