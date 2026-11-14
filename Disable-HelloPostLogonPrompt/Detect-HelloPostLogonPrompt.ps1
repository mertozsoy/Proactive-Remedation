<#
.SYNOPSIS
  Detection script for the forced Windows Hello for Business setup prompt after sign-in.

.DESCRIPTION
  Checks whether Windows Hello for Business provisioning after sign-in is turned off. Exits 1 if the prompt can still appear and no MDM policy manages it, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SkipDomainJoinedWithoutPolicy = $true

$PackageName = 'HelloPostLogonPrompt'
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

$GpoKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'
$MdmRoot = 'HKLM:\SOFTWARE\Microsoft\Policies\PassportForWork'

function Get-MdmHelloPolicy {
    foreach ($tenant in Get-ChildItem -LiteralPath $MdmRoot -ErrorAction SilentlyContinue) {
        $policy = Get-ItemProperty -LiteralPath (Join-Path $tenant.PSPath 'Device\Policies') -ErrorAction SilentlyContinue
        if ($null -ne $policy.UsePassportForWork -or $null -ne $policy.DisablePostLogonProvisioning) {
            return [pscustomobject]@{ UsePassportForWork = $policy.UsePassportForWork; DisablePostLogonProvisioning = $policy.DisablePostLogonProvisioning }
        }
    }
    return $null
}

function Get-GpoHelloPolicy {
    $policy = Get-ItemProperty -LiteralPath $GpoKey -ErrorAction SilentlyContinue
    [pscustomobject]@{ Enabled = $policy.Enabled; DisablePostLogonProvisioning = $policy.DisablePostLogonProvisioning }
}

function Format-Value { param($Value) if ($null -eq $Value) { 'NotSet' } else { "$Value" } }

try {
    $mdm = Get-MdmHelloPolicy
    if ($mdm) { Exit-Script 0 "ManagedByMDM | UsePassportForWork=$(Format-Value $mdm.UsePassportForWork); DisablePostLogonProvisioning=$(Format-Value $mdm.DisablePostLogonProvisioning)" }

    $gpo     = Get-GpoHelloPolicy
    $summary = "Enabled=$(Format-Value $gpo.Enabled); DisablePostLogonProvisioning=$(Format-Value $gpo.DisablePostLogonProvisioning)"

    if ($gpo.Enabled -eq 0) { Exit-Script 0 "Compliant | $summary; Hello=Disabled" }
    if ($gpo.DisablePostLogonProvisioning -eq 1) { Exit-Script 0 "Compliant | $summary" }

    $domainJoined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    if ($SkipDomainJoinedWithoutPolicy -and $domainJoined -and $null -eq $gpo.Enabled) { Exit-Script 0 "NotApplicable | $summary; DomainJoined=True" }

    Exit-Script 1 "PromptEnabled | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
