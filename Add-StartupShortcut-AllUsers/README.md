# Add Startup Shortcut for All Users

Utility script (not a Detect/Remediate pair) that creates a `.lnk` shortcut to a given application in the all-users Startup folder, so the app launches automatically for every user who logs into the device.

## Files

| File | Purpose |
|---|---|
| `Add-StartupShortcut-AllUsers.ps1` | Builds a shortcut path from a target application folder/exe name and creates it in `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup` using the WScript Shell COM object. |

## Usage

Edit the two placeholder variables at the top of the script before running:

```powershell
$uygulamaYolu = "Uygulamanin kurulu oldugu klasor yolu"   # path to the folder containing the app's .exe
$uygulamaAdi  = "UygulamaExeAdi.exe"                       # the executable file name
```

## Deployment (Intune)

1. Fill in the two variables for the specific application you want to auto-start.
2. Deploy as a **Win32 app install script** or a one-time **Proactive Remediation** remediation script (with a matching detection script that checks whether the shortcut already exists, if you want it idempotent/reportable).
3. Run in the **system context** (required to write to the all-users `ProgramData` Startup folder).

## Notes

- This is a generic template with placeholder values — it must be customized per application before use.
- No environment-specific values are present beyond the placeholders you fill in.
