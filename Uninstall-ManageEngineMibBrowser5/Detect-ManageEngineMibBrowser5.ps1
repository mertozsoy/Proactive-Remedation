$AppGUID = "{9C79392A-ACA0-4253-A57A-B29A53205273}"

$Found = Get-ChildItem `
"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
Where-Object { $_.PSChildName -eq $AppGUID }

if ($Found) {
    Write-Output "ManageEngine MibBrowser 5 bulundu."
    exit 1
}
else {
    Write-Output "ManageEngine MibBrowser 5 bulunamadi."
    exit 0
}
