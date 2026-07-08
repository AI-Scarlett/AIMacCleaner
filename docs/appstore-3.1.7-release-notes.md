# TraceFence 3.1.7 App Store Metadata

## Review Notes

TraceFence 3.1.7 fixes Mac Cleaner storage accounting for Docker Desktop sparse disk images and makes AI Disk Advisor scan/analyze progress much easier to see. The App Store build continues to use sandbox-safe local file access: users review detected cleanup candidates before anything is moved to Trash, and the app does not include proxy/VPN traffic interception, root certificate installation, or third-party model credentials.

## Build Notes

- Build: 66
- Architecture: arm64 Mac App Store package.
- Release metadata: `BuildMachineOSBuild` must be overridden to `25F70` before export so the package does not leak the beta macOS host build.

## What's New

- Fixes Docker image/container storage reporting when Docker.raw is a sparse disk image.
- Counts actual allocated disk blocks instead of virtual logical disk-image capacity.
- Discards old cached cleanup scan results after update so previously oversized Docker values do not remain visible.
- Caps cleanup totals to the current disk used amount as a final UI safeguard.
- Makes AI Disk Advisor scan/analyze activity more visible with the same radar-style status indicator used by Overview.

## Promotional Text

More accurate Docker cleanup sizing and clearer AI Disk Advisor scan progress.

## Keywords

AI quota,reset credits,Docker cleanup,Mac storage,token usage,model attribution
