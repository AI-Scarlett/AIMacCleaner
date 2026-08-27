# Network Traffic implementation decisions

| Decision | Objective | Benefit | Cost | Evidence gate | Reconsider when |
| --- | --- | --- | --- | --- | --- |
| Native TraceFence plugin, not a Sniffnet wrapper | Fit the existing `.mactoolsplugin` host | Independent updates, native UI, no second desktop runtime | Reimplements a bounded subset | Bundle build and Host loading | Sniffnet publishes a stable embeddable API |
| Safe socket mode is the default | Provide useful live monitoring without root | Process and connection attribution work with normal user privileges | No packet payload or PCAP export | Fixed-argv `nettop` parser tests and runtime smoke | macOS provides a supported unprivileged packet API |
| Raw libpcap is explicit and fail-closed | Enable BPF filtering and PCAP export where authorized | Standard capture semantics without changing system policy | Normal macOS BPF permissions may reject capture | Permission-denied path plus disposable raw-capture test | A reviewed privileged helper is designed and signed |
| No automatic administrator helper | Avoid running TraceFence or arbitrary plugin code as root | Keeps privilege boundary narrow and recoverable | Live raw capture may be unavailable | No `sudo`, AppleScript, chmod, launchd, or shell paths in source | A separately threat-modeled helper is approved |
| Bounded metadata and raw-frame retention | Prevent memory and privacy blowups | Stable long-running behavior and honest truncation | Old details are evicted | Unit tests for caps and export bounds | Measured user workflows require larger limits |
| No geolocation/ASN network calls in 0.1.0 | Avoid hidden external disclosure | Zero third-party lookup traffic or database licensing | Host location/ASN is unavailable | Network scan shows only `nettop` and libpcap | A local licensed database is packaged or opt-in API is approved |

Current evidence target is local source/build/tests only. Installation, catalog publication, signed release, real-user raw capture, and public distribution are separate gates.
