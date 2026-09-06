<#
Version: 1.0
Author: 
- Jorgen Nilsson (ccmexec.com)
Script: Remediate-PCManager.ps1
Description:
Hint: This is a community script. There is no guarantee for this. Please check thoroughly before running.
Version 1.0: Init
Run as: Admin
Context: 64 Bit
#> 

#Define AppID
$AppID = "633f5f69-8cd1-433c-8223-ccd983724885"

try {
    # Remove Store package
    Get-AppxPackage -Name "Microsoft.MicrosoftPCManager" -AllUsers | Remove-AppxPackage -AllUsers
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Host $errorMessage
    exit 1
}

#Clear IME registry values
$Regpath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"
Get-ChildItem -Path $Regpath -Recurse -Exclude "*AppAuthority*" | Where-Object { $_.PSChildName -like "*$AppId*" -or $_.Property -like "*$AppId*" } | Remove-Item -Recurse -Force

#Restart IME service
Start-Process -FilePath powershell -ArgumentList '-Executionpolicy bypass -command "& {Start-Sleep 160 ; Restart-Service -Name IntuneManagementExtension -Force}"'

#Exit script
Exit 0
