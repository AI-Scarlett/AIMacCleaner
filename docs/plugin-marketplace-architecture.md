# TraceFence direct-build plugin marketplace

## Repository boundary

TraceFence application source, Xcode projects, signing private keys, Dodo API
keys, customer licenses, and runtime data stay in the private source repository
or local secure storage. They must never be copied to the public GitHub
distribution repository.

The public `AI-Scarlett/TraceFence` repository may contain only:

- the signed storefront catalog and detached signature;
- signed plugin packages, hashes, icons, and public plugin documentation;
- already-approved installer and update artifacts.

`scripts/marketplace/export_public_catalog.py` is the fail-closed export path.
It refuses any public destination except the distribution repository and only
copies the three catalog whitelist files.

## Entitlement model

- A free plugin is available without a license.
- A paid plugin can grant a single 24-hour local trial.
- A standalone license is accepted only when the Dodo activation response's
  business and product IDs match that exact plugin offer.
- An active TraceFence Standard license grants all plugins marked
  `includedInAllAccess`.
- A standalone Dodo product cannot be shared by multiple plugins. The public
  activation response does not provide a trustworthy client-controlled binding
  from a generic product to an arbitrary plugin ID.
- Dodo Checkout is the charge authority. The signed catalog controls display,
  routing, and expected product IDs; the client never submits a price to the
  checkout page.

## Catalog trust chain

1. Edit `catalog/storefront-v1.source.json` in the private checkout.
2. Validate IDs, product ownership, package origins, hashes, bundle IDs, Team
   ID, version ranges, and offer relationships.
3. When prices change, synchronize them to Dodo and read the values back.
4. Canonicalize and sign the exact JSON bytes with the offline Ed25519 private
   key. Only the public key is compiled into TraceFence.
5. Export only JSON, detached signature, and public catalog documentation.
6. The client rejects redirects, oversized responses, unknown keys, invalid
   signatures, expired documents, unsafe package URLs, and revision rollback.
7. If refresh fails, TraceFence continues with the last verified cache or the
   built-in fallback catalog.

## Performance contract

Installing many plugins must not start many scanners or services.

- Catalog parsing is bounded and cached; it does not enumerate package
  contents during normal startup.
- A plugin is activated only when the user opens its feature or explicitly
  enables its background capability.
- Disabled and locked plugins must not register timers, file watchers, network
  listeners, or menu-bar polling jobs.
- Package installation and validation run off the main actor. UI publication is
  reduced to small immutable snapshots.
- Each plugin receives explicit capabilities and storage roots. It must not
  inherit every host permission.
- Background plugins need a declared memory budget, CPU duty-cycle budget,
  cancellation path, and health status. Repeated crashes disable the plugin
  instead of restarting forever.

## Migration stages

### A. Storefront and entitlement boundary (implemented on this branch)

- Signed remote catalog with cached fallback and rollback protection.
- Dynamic Standard pricing and checkout product mappings.
- Free, Standard, standalone-license, and one-time trial access states.
- Plugin Store UI and direct-build feature gates.
- iOS Remote Pairing listener stops when its plugin entitlement is unavailable.
- Public catalog export and private Dodo synchronization tooling.

Existing modules are declared as `built_in` during this stage. This creates a
commercial and lifecycle boundary without loading arbitrary code into the host.

### B. Built-in module lifecycle

Move each module's startup work behind `prepare`, `activate`, `deactivate`, and
`snapshot` boundaries. Start with Token & Usage, Agent Guard, Disk Advisor, and
iOS Remote Pairing because they own the largest scans, watchers, or listeners.

### C. Signed downloadable packages

Add an installer that streams to a staging directory, enforces the declared
size, verifies SHA-256, validates code signing and Team ID, rejects symlinks and
path traversal, then atomically switches versions. Keep the previous known-good
version for rollback.

### D. Process isolation

Run third-party or higher-risk plugins in a constrained XPC service. Keep simple
first-party UI-only extensions in-process only after measuring their memory and
startup cost. Plugin count alone must have near-zero idle cost.

### E. Product operations

Provision one Dodo product per standalone paid plugin, add it to the catalog,
run test-mode activation/deactivation, then enable the offer. A private binding
service is required before supporting a generic license key that can be redeemed
for an arbitrary plugin.
