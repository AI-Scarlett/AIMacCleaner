# TraceFence model pricing catalog

`model-pricing-v1.json` is the versioned, public source for API-equivalent cost estimates in the TraceFence direct-download client. It uses USD per one million tokens and the providers' standard processing tier. Estimates are informational and are not provider invoices.

The client accepts this file only from the fixed HTTPS GitHub endpoint. It validates the schema, model identifiers, dates, ranges and every numeric rate; keeps the last valid catalog with ETag metadata; and falls back to its built-in catalog when the network or file is invalid.

## Updating prices

1. Verify the values against an official provider pricing page and changelog.
2. Preserve historical prices. End the old entry with `effectiveUntil` and add a new entry with the same instant in `effectiveFrom`.
3. Increase `catalogVersion` and `updatedAt` whenever content changes.
4. Keep the document below 256 KiB and use non-negative finite rates only.
5. Validate the JSON and run the TraceFence pricing self-test before merging.

Do not use a zero rate for an unknown or unpublished price. Omit the model instead so TraceFence can label its estimate as unavailable. When a provider does not publish a cached-input or cache-write rate, omit that field; the client conservatively falls back to the normal input rate.
