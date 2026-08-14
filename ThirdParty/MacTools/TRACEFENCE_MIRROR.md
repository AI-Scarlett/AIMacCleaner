# MacTools plugin source mirror

This directory is a pinned source mirror used to build TraceFence-distributed
plugin packages. TraceFence clients never download code or catalog data from
the upstream repository at runtime.

The mirrored code comes from `ggbond268/MacTools`, is licensed under the Apache
License 2.0, and retains the upstream license and third-party notices. Package
artifacts built from this snapshot must be published only through the
`AI-Scarlett/TraceFence` distribution repository with immutable versioned URLs
and SHA-256 values recorded in the signed TraceFence catalog.

Do not edit mirrored source files directly. Update the snapshot with
`scripts/marketplace/sync_mactools_vendor.py`, review the upstream diff, rebuild
all packages, and verify the public assets before advancing the catalog.

`project.upstream.yml` preserves the upstream XcodeGen project. The active
`project.yml` removes the host-only Sparkle package from the build graph so a
plugin-only mirror build does not depend on an unrelated network checkout.
`scripts/plugins/build-local-plugins.upstream.sh` preserves the upstream
builder; the active copy reuses one DerivedData directory for the pinned batch
to keep full-catalog builds bounded and reproducible on the release host.
