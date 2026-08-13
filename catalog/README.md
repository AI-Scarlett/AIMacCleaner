# TraceFence public marketplace catalog

This directory is the only public-catalog input maintained beside the private
TraceFence source checkout. It is exported to the public `AI-Scarlett/TraceFence`
distribution repository by `scripts/marketplace/export_public_catalog.py`.

The public repository may contain only:

- canonical signed catalog JSON and detached signature envelope;
- signed plugin packages, package hashes, icons, and public documentation;
- public installer/update manifests already approved for distribution.

It must never receive the TraceFence Xcode project, Swift sources, scripts that
contain application implementation, signing private keys, Dodo API keys, or
runtime/customer data.

## Price changes

Edit `storefront-v1.source.json`, increment `revision`, update `publishedAt` and
`expiresAt`, then run the private validation/sync workflow. A production publish
must first synchronize each changed price to Dodo, read it back, and only then
sign and export the canonical catalog. If Dodo synchronization or readback fails,
the public catalog must not be replaced.

The client treats Dodo Checkout as the final billing authority. Catalog prices
are authenticated display/configuration data, not client-supplied charge values.

## Signing

The signing key is stored outside this repository. Only its Ed25519 public key
is embedded in TraceFence. The detached `.sig` envelope covers the exact bytes
of the canonical JSON file.
