# Set Teams Custom Backgrounds

Intune Remediations script pair. Corporate meeting backgrounds disappear from the new Teams client after an update, a profile reset or a device replacement, and users have to upload the images by hand. This pair compares a staging folder with the signed-in user's Teams Uploads folder and copies the missing images back.

## Files

| File | Purpose |
|---|---|
| `Detect-TeamsCustomBackgrounds.ps1` | Runs as the user. Reads the jpg, jpeg and png files in `$SourceFolder` and compares each one with the `Corp-` prefixed copy in the new Teams Uploads folder. Name and size are checked. Exits 1 when a file is missing or differs in size. |
| `Remediate-TeamsCustomBackgrounds.ps1` | Creates the Uploads folder if needed, copies the missing or stale images and verifies the result. Only files with `$TargetPrefix` are written, so personal uploads are never touched. |

## Deployment (Intune)

1. Stage the background images in `C:\ProgramData\Company\TeamsBackgrounds` with a Win32 app or a separate script.
2. Go to **Devices > Scripts and remediations > Remediations > Create**.
3. Upload `Detect-TeamsCustomBackgrounds.ps1` as the detection script and `Remediate-TeamsCustomBackgrounds.ps1` as the remediation script.
4. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
5. Schedule: Daily. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- Keep `$SourceFolder` and `$TargetPrefix` identical in both scripts. The staging folder must be readable by standard users.
- Only `.jpg`, `.jpeg` and `.png` files are copied. Teams shows the file name in the background gallery.
- Teams reads the Uploads folder at start. The new images appear after the user restarts Teams. The script does not close the app.
- This is a local workaround. Teams Premium organizations should use the customization policy in the Teams admin center instead.
- Placing files in the Uploads folder is not supported for VDI optimization. There, users must upload the image through Teams.
