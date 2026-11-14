# Repair WebView2 Runtime

A missing or damaged WebView2 Runtime can prevent Teams, new Outlook and other apps from opening. These scripts check the machine-wide Evergreen installation and run a Microsoft-signed installer when files or registration are missing.

## Files

| File | Purpose |
|---|---|
| `Detect-WebView2Runtime.ps1` | Checks the documented machine registration, version folder, executable signature and presence of a nonempty runtime DLL. Returns 1 when these checks fail. |
| `Remediate-WebView2Runtime.ps1` | Downloads the Evergreen Bootstrapper or uses `$InstallerPath`, runs `/silent /install` as SYSTEM and repeats detection. An optional registration reset handles stale registrations after an unsuccessful install. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Name: **Repair - WebView2 Runtime**. Upload the detection and remediation scripts.
3. Run this script using the logged-on credentials: **No**.
4. Enforce script signature check: **No**. Run script in 64-bit PowerShell: **Yes**.
5. Assign to a pilot device group. Schedule daily and review results before expanding.

## Notes

- Covers standard machine-wide Evergreen files only, not application startup, every DLL, per-user installs, Fixed Version runtimes or ARM architecture mismatches. Keep custom `$RuntimeRoots` identical in both scripts.
- The default download needs SYSTEM internet access. For offline devices set `$InstallerPath` to a locally staged, architecture-matched Evergreen Standalone Installer in an administrator-controlled folder. Installer signatures must be valid and belong to Microsoft.
- Applicable Edge Update installation, update or runtime-specific policies return `PolicyManaged` without changes, even when permissive. Review the owning policy rather than bypassing it.
- `$ResetBrokenRegistration = $false` protects the advanced fallback. Enable only after pilot approval: it exports the runtime client key to `%ProgramData%\IntuneRemediations\Backup`, removes that key and reinstalls only if runtime files remain missing and runtime/setup processes are absent. Failed reinstall restores missing registration when setup is idle.
- No apps are closed and no restart is requested. `Fixed` requires successful file checks; persistent damage returns `Failed`. Signature trust failures can also reflect certificate or network issues. Ask users to reopen affected apps after installation.
