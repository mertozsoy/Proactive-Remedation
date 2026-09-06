$AppGUID = "{ED41CD4E-33BB-400C-AB20-B09388DC83EF}"

$Found = Get-ChildItem `
"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
Where-Object { $_.PSChildName -eq $AppGUID }

if ($Found) {
    Write-Output "PuTTY release 0.83 (64-bit) bulundu."
    exit 1
}
else {
    Write-Output "PuTTY release 0.83 (64-bit) bulunamadi."
    exit 0
}
