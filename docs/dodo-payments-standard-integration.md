# TraceFence Standard - Dodo Payments Integration

Updated: 2026-07-14

## Current Status

The Release configuration uses Dodo Payments Live Mode. Both production checkout pages were verified before packaging, and both resolve to the configured Dodo business.

| Billing period | Product | Live product ID | Price |
| --- | --- | --- | --- |
| Monthly | TraceFence Standard - Monthly | `pdt_0Nj4q5PqaHwgy17MmjlAk` | $9.99/month |
| Annual | TraceFence Standard - Annual | `pdt_0Nj4rXdh9EI3A7uzyYWpk` | $79.99/year |

Debug/Internal builds retain these isolated Test Mode products:

| Billing period | Product | Test product ID | Price |
| --- | --- | --- | --- |
| Monthly | TraceFence Standard - Monthly | `pdt_0Nj4pRs43qM7S5NM2yl2D` | $9.99/month |
| Annual | TraceFence Standard - Annual | `pdt_0Nj4pnQWqPMk14yHT9Q1i` | $79.99/year |

Configured Dodo business ID: `bus_0Nj3ve514BLr8z2wT3duj`.

There is one entitlement level: TraceFence Standard. Monthly and annual are billing choices for the same feature set. Website Enhanced is not offered.

Both current Live Mode products and both retained Test Mode products include a two-day free trial.

## Client Flow

1. A Release build constructs a Live Mode checkout URL under `https://checkout.dodopayments.com/buy/{product_id}`. Debug/Internal builds use `https://test.checkout.dodopayments.com/buy/{product_id}`.
2. Dodo Payments handles checkout, tax, invoices, and subscription lifecycle.
3. Both products must include a Dodo License Key entitlement.
4. The checkout return page receives `subscription_id`, `status`, `license_key`, and `email` from Dodo Payments.
5. The user pastes the key into TraceFence Settings.
6. Release builds call the public Live Mode license endpoints directly:
   - `POST https://live.dodopayments.com/licenses/activate`
   - `POST https://live.dodopayments.com/licenses/validate`
   - `POST https://live.dodopayments.com/licenses/deactivate`
   Debug/Internal builds call the corresponding `https://test.dodopayments.com/licenses/*` endpoints.
7. The license key and activation instance ID are stored in macOS Keychain. Business, product, and validation metadata are cached locally.

The public license lifecycle endpoints do not require an API key. No Dodo Payments API secret may be embedded in the Mac app, iOS app, website, pairing payload, or source-controlled configuration.

## Test And Production Isolation

- Debug/Internal builds keep the current Test Mode business, monthly product, and annual product as their bundled defaults.
- Debug/Internal Settings expose local environment, business ID, monthly product ID, and annual product ID overrides. Changing a test product therefore does not require rebuilding that internal app.
- Release builds compile out local Dodo overrides and read only their bundled configuration. Values left in `UserDefaults` by a Debug build cannot redirect a production checkout or license validation.
- Release is pinned to Live Mode and the production business/monthly/annual IDs. Debug remains pinned to the current Test Mode products for later entitlement work.
- A future Enhanced entitlement still requires application code that understands the new tier. After that support exists in an Internal build, its test product mapping can use the same runtime configuration pattern without affecting production users.

## Product Validation

The activation response must report both the configured Dodo business ID and one of the two configured product IDs. A valid Dodo key issued by another business or for any other product is rejected. License validation includes the activation instance ID so a key cannot silently move between devices without using the deactivation flow.

When a previously validated license cannot reach Dodo Payments because of a transient network or server failure, TraceFence keeps the cached entitlement for up to 72 hours. A definitive invalid response disables the entitlement immediately.

## Test Checklist

- Monthly checkout opens in Test Mode and displays `TraceFence Standard - Monthly` at `$9.99`.
- Annual checkout opens in Test Mode and displays `TraceFence Standard - Annual` at `$79.99`.
- A successful test purchase returns a license key.
- A monthly key activates, validates after app restart, and deactivates.
- An annual key activates, validates after app restart, and deactivates.
- A random key is rejected.
- A key from another Dodo business is rejected even if Dodo says it is valid.
- A key from another Dodo product is rejected even if Dodo says it is valid.
- An activation beyond the product's configured device limit is rejected.
- Cancellation or entitlement revocation makes validation return invalid.
- The checkout success page removes the license key from the visible browser URL after rendering it.
- A Debug build accepts valid local Dodo configuration overrides without rebuilding.
- A Release build ignores all local Dodo configuration overrides.

## Production Verification

The Release bundle must contain `live`, business `bus_0Nj3ve514BLr8z2wT3duj`, and only the two Live product IDs above. It must not contain either Test Mode product ID. The signed package, public update manifest, checksum, and purchase-success page must be verified after every production upload.

Complete one low-value live transaction after release to verify purchase, license activation, restart validation, deactivation, cancellation, and refund behavior against the production account. This operational transaction cannot be simulated with only the public product metadata.

The TestFlight fallback for TraceFence Sentinel is `https://testflight.apple.com/join/yZTXmaJ8` and is displayed separately from the Mac pairing QR code.
