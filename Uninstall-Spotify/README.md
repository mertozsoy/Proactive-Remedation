# Uninstall Spotify (Microsoft Store)

Intune Proactive Remediation script pair that detects and removes the **Spotify** Microsoft Store app (package family `SpotifyAB.SpotifyMusic_zpdnekdrzrea0`) for all users on a device.

## Files

| File | Purpose |
|---|---|
| `Detect-Spotify.ps1` | Checks `Get-AppxPackage -AllUsers` for the Spotify package family. Exits `1` if found, `0` if not found. |
| `Remediate-Spotify.ps1` | Stops running Spotify/SpotifyMigrator processes, removes the Appx package for all users, removes the provisioned package, then verifies removal. Exits `1` if still present, `0` on success. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context**.
4. Assign to the target device group.

## Notes

- No environment-specific values are present in these scripts.
- This targets the Microsoft Store (UWP) build of Spotify only, not the standalone desktop installer.
