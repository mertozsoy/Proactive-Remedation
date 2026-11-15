# Disable Desktop Hibernation

Desktop devices keep `hiberfil.sys` even when nobody hibernates them. The file is about 40 percent of physical memory, so a 32 GB desktop gives up more than 12 GB of disk. The file also comes back after a cleanup when hibernation is still enabled. These scripts find the file on desktops and remove it, or shrink it to a reduced hiberfile when fast startup has to stay.

## Files

| File | Purpose |
|---|---|
| `Detect-DesktopHibernation.ps1` | Checks the chassis type, `HibernateEnabled`, `HiberFileSizePercent` and the size of `hiberfil.sys`. Exits 1 when a desktop keeps a hibernation file. `$HibernateMode` switches the check to the reduced size ceiling. |
| `Remediate-DesktopHibernation.ps1` | Runs `powercfg /hibernate off`, deletes a leftover file when one remains, then re-checks the registry value and the file. In `Reduce` mode it runs `powercfg /hibernate /size 0` and `powercfg /hibernate /type reduced`. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DesktopHibernation.ps1` as the detection script and `Remediate-DesktopHibernation.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
4. Schedule: once for the fleet, daily for new images.
5. Assign to a pilot group of desktops first, check the output, then widen the scope.

## Notes

- Set `$HibernateMode = 'Reduce'` in both scripts to shrink the file to a reduced hiberfile of about 20 percent of RAM for fast startup instead of removing it.
- Laptops, tablets and servers exit as NotApplicable. Set `$DesktopOnly = $false` to run the scripts on any client.
- In Remove mode hibernate and hybrid sleep disappear from the power menu and fast startup is turned off.
- `$RemoveOrphanedFile = $true` deletes a hiberfil.sys that `powercfg` leaves behind on devices where hibernation was already off.
- A policy or tool that allows hibernation can create the file again. Exclude those devices or change the policy. The `powercfg` exit code and the file size before and after are logged.
