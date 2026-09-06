Start-Transcript -Path $env:TEMP\DisableFastBoot.txt
if((Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power") -ne $true) {  
  write-host "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power does not exist"
  New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -force -ea SilentlyContinue
write-host "Key Created" };
New-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0 -PropertyType DWord -Force -ea SilentlyContinue;
write-host "Value Set"

Stop-Transcript