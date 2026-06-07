# Release and Distribution

## Branches

- `dev` is the working branch for implementation.
- `main` should be aligned after verified changes when requested.
- Do not leave requested fixes only in the working tree.

## Build Verification

For local macOS verification:

```bash
xcodebuild -project AIMacCleaner.xcodeproj \
  -scheme AIMacCleaner \
  -configuration Debug \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO build
```

Install a local build for manual validation:

```bash
BUILT="$HOME/Library/Developer/Xcode/DerivedData/AIMacCleaner-enfbfqhrsshkslaxhjiymqhpppuz/Build/Products/Debug/AgentGuard.app"
DEST="$HOME/Applications/AgentGuard.app"
pkill -x AgentGuard || true
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
codesign --force --deep --sign - --entitlements AIMacCleaner/AIMacCleaner.entitlements "$DEST"
codesign --verify --deep --strict "$DEST"
open -n "$DEST"
```

## DMG Release Rule

When publishing a DMG release, upload only the built app package or DMG artifact. Do not upload source archives as product release assets unless explicitly requested.

## Runtime Checks

After installation:

- Confirm `AgentGuard` is running.
- Check recent crash reports under `~/Library/Logs/DiagnosticReports`.
- Verify cache-backed pages show existing data immediately.
- Verify background scans update the last scan time and overwrite stale cache records.
