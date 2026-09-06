if (!(Test-Path "C:\Temp")) {
    New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path "C:\Temp\CredentialGuardDetection.txt" -Force

try {
    Write-Host "Setting LsaCfgFlags to 0..."

    New-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
        -Name "LsaCfgFlags" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    $CurrentValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LsaCfgFlags").LsaCfgFlags

    Write-Host "Current LsaCfgFlags value: $CurrentValue"
    Write-Host "Operation completed successfully."

    Stop-Transcript
    Exit 0
}
catch {
    Write-Host "Error: $($_.Exception.Message)"

    Stop-Transcript
    Exit 1
}