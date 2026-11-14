# Remediate Delivery Optimization Cache

Intune Remediations script pair. The Delivery Optimization cache can grow to tens of GB and Disk Cleanup does not always give the space back. This pair finds oversized caches and clears them with the built-in cmdlet.

## Files

| File | Purpose |
|---|---|
| `Detect-DeliveryOptimizationCache.ps1` | Measures the cache folder under the NetworkService profile. Flags it when it is over `$MaxCacheGB` (10) or when free space is under `$LowFreePercent` (15) and the cache takes more than `$MaxCachePercentLow` (5) percent of the disk. Reports the DOMaxCacheSize and DOAbsoluteMaxCacheSize policy values. |
| `Remediate-DeliveryOptimizationCache.ps1` | Runs `Delete-DeliveryOptimizationCache -Force`, measures the folder again and reports the freed size. Pinned files are kept. |

## Deployment (Intune)

1. Go to **Devices > Scripts and remediations > Remediations > Create**.
2. Upload `Detect-DeliveryOptimizationCache.ps1` as the detection script and `Remediate-DeliveryOptimizationCache.ps1` as the remediation script.
3. Run this script using the logged-on credentials: **No**. Run script in 64-bit PowerShell: **Yes**.
4. Schedule: Daily.
5. Assign to a pilot group first, check the output, then widen the scope.

## Notes

- If the cache drive was moved with the DOModifyCacheDrive policy, detection returns NotApplicable.
- Clearing the cache does not stop peer to peer. Devices simply download again from the source or from peers when they need the content.
- The long term fix is a cache size limit in Settings Catalog (Delivery Optimization > Absolute Max Cache Size or Max Cache Size).
