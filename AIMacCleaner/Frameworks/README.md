# Plugin compatibility framework

`MacToolsPluginKit.framework` is a generated compatibility runtime for the
pinned first-party plugin migration. Its complete Apache-2.0 source is mirrored
under `ThirdParty/MacTools`, and
`scripts/plugins/build_compatibility_framework.sh` reproduces the universal
framework embedded in TraceFence.

This internal module name remains only for binary compatibility with the pinned
packages. New public plugin APIs will use TraceFence naming and an explicitly
versioned contract.
