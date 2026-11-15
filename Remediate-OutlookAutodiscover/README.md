# Remediate Outlook Autodiscover

In an Exchange hybrid organization Outlook can pick a lookup method that does not lead to the on-premises endpoint. The client tries the root domain of the primary SMTP address or the built in Microsoft 365 endpoint, the user gets a certificate warning and the mailbox ends up on the wrong place. This pair sets the documented Autodiscover DWORDs so the client keeps using SCP and the autodiscover domain.

## Files

| File | Purpose |
|---|---|
| `Detect-OutlookAutodiscover.ps1` | Runs as the user. Reads four DWORDs under `HKCU\Software\Microsoft\Office\16.0\Outlook\AutoDiscover`, skips values that a policy also sets, and exits 1 when a lookup aimed at the root domain or at Microsoft 365 is still enabled. |
| `Remediate-OutlookAutodiscover.ps1` | Exports the current key, writes `ExcludeHttpsRootDomain` and `ExcludeExplicitO365Endpoint` as 1 and the two opposite values as 0, then reads the key again to verify. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-OutlookAutodiscover.ps1` as the detection script and `Remediate-OutlookAutodiscover.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **Yes**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily. Assign to a user group, not a device group.
5. Start with a pilot group, check the output, then widen the scope.

## Notes

- Edit `$ExpectedValues` in both scripts and keep the map identical. In a tenant without on-premises mailboxes set `ExcludeExplicitO365Endpoint` to 0, otherwise the client loses the cloud endpoint.
- A value under `HKCU\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover` or under the same path in `HKLM` wins over the user hive. Those entries are reported as `Policy` and left alone.
- `ExcludeScpLookup` must stay at 0 in hybrid. SCP lookup is how the client finds the on-premises endpoint.
- `$OfficeVersion` is 16.0, which covers Outlook 2016, Outlook 2019 and Microsoft 365 Apps. Outlook 2013 stores the same values under 15.0.
- `$EnableRemediation = $false` by default: the pair only reports until you set `$ExpectedValues` for your tenant and enable it. The key is per user and Outlook reads it at start, so nothing is closed or restarted.
