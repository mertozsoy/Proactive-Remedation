$AppGUID = "{E3B69BB6-FFD8-441C-933E-BB8A3136ED8F}"

$Found = Get-ChildItem `
"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
Where-Object { $_.PSChildName -eq $AppGUID }

if ($Found) {
    Write-Output "Google Earth Pro bulundu."
    exit 1
}
else {
    Write-Output "Google Earth Pro bulunamadi."
    exit 0
}
