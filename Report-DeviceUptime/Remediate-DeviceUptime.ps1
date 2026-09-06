<#
.SYNOPSIS
    No-op remediation script for Windows uptime reporting.

.DESCRIPTION
    Uptime reporting does not require automatic remediation. This file exists
    so the package can be uploaded as an Intune Remediations pair.

.NOTES
    Version: 1.0
    Run As: System
#>

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::WriteLine("No automated remediation. Uptime is collected by the detection script.")
exit 0
