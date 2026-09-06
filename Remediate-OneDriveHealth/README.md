# Remediate OneDrive Health

Intune Proactive Remediation script pair that checks whether OneDrive is signed in and syncing correctly for the logged-on user, and attempts a full self-heal (restart, silent re-config, cache cleanup) if it isn't.

## Files

| File | Purpose |
|---|---|
| `Detect-OneDriveHealth.ps1` | Finds the logged-on user, reads their Business OneDrive account registry key, confirms the OneDrive process is running, then parses the latest `SyncDiagnostics.log` for a `SyncProgressState` value. Flags known error codes (`65536`, `8194`, `1854`, `1580`) as unhealthy. Exits `1` on any failure, `0` if healthy. |
| `Remediate-OneDriveHealth.ps1` | Multi-step self-heal: (1) ensures the startup registry entry exists, (2) starts OneDrive if not running — using a P/Invoke helper to launch it in the interactive user's session when running as SYSTEM, (3) if no account is configured and Silent Account Configuration policy is enabled, clears stale OneDrive registry/cache data and lets it silently re-provision, (4) restarts the process and clears `.db-wal`/`.db-shm` pause-state files to unstick a stuck sync engine. Always exits `0`. |

## Deployment (Intune)

1. Create a new **Proactive Remediation** in Intune.
2. Upload both scripts as detection/remediation.
3. Run in the **system context** — required for the `CreateProcessAsUser` trick that launches OneDrive in the logged-on user's session, and for reading `HKEY_USERS`.
4. For step 3 of the remediation (silent re-provisioning) to fire, `HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\SilentAccountConfig` must be enabled via your OneDrive ADMX policy / Silent Account Configuration setup.
5. Assign to the target device group.

## Notes

- No hardcoded environment-specific values (emails, tenant IDs, hostnames) are present — the script discovers the logged-on user and their OneDrive account dynamically at runtime.
- Only targets the "Business" (work/school) OneDrive account type; personal OneDrive accounts are not evaluated.
