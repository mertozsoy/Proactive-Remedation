# Remove Extra Office Products

Preinstalled Office editions can remain alongside Microsoft 365 Apps. These scripts detect selected Click-to-Run product IDs and remove them with the Office Deployment Tool while preserving other products.

## Files

| File | Purpose |
|---|---|
| `Detect-ExtraOfficeProducts.ps1` | Checks installed Click-to-Run product IDs against the removal list. |
| `Remediate-ExtraOfficeProducts.ps1` | Removes approved products with ODT and verifies removed and preserved IDs. |

## Deployment (Intune)

1. Align Office application assignments and installation XML with the intended product list before approving removal.
2. Stage the current Microsoft Office Deployment Tool setup.exe at `$OdtPath` using a separate managed deployment with administrator-only write access. Set `$OdtSha256` to its trusted SHA256 hash.
3. Keep `$RemoveProductIds` and `$RequiredSuiteIds` identical in both scripts. Set `$EnableRemediation = $true` after reviewing the removal list.
4. Go to **Devices > Scripts and remediations > Remediations > Create**. Upload both scripts.
5. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**. Enforce script signature check: **No** for unsigned scripts.
6. Assign to a pilot group first. Schedule daily outside working hours.

## Notes

- Removal starts disabled. Defaults target listed consumer editions only; add `OneNoteFreeRetail` only if standalone OneNote is unwanted.
- A Microsoft 365 Apps suite must already be present. Project, Visio and Microsoft 365 suite IDs cannot be removal targets.
- Language-only cleanup remains manual because a reliable local C2R language inventory was not verified; MSI and Store editions are outside scope.
- Open Office apps or an installer defer removal. Apps are never forced closed; no restart is requested. A timed-out installer is left running.
- No policy values are changed. Success verifies product IDs, not application health; reinstall the removed edition through managed deployment if rollback is needed.
