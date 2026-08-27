# Network Traffic security boundary

This plugin observes network metadata. It never displays packet payload bytes, never acts as a firewall, and never modifies system packet-filter rules.

- Safe live mode launches only `/usr/bin/nettop` with a fixed argument array. It does not use a shell, administrator authorization, credentials, or a listener.
- Raw capture mode uses the system `libpcap` API and opens only the interface explicitly selected by the user. On normal macOS BPF permissions this can fail with `permission denied`; the plugin reports the limitation and does not run TraceFence as root or change `/dev/bpf*` permissions.
- PCAP import reads only a file selected by the user. At most 10,000 packets and 32 MiB of retained frame data are accepted per analysis.
- PCAP export writes only to a destination selected by the user and only from retained raw frames. Safe live-mode socket summaries cannot be misrepresented as packet captures.
- Connection history is memory-bounded. Persisted preferences contain only the selected interface/mode/filter plus user-entered favorite and blacklist host strings.
- Blacklist matches create in-app alerts only. This plugin does not block, reroute, terminate, or inject traffic.

Raw capture data can include sensitive addresses and payloads even though payloads are not rendered. Users should protect exported PCAP files and share them only after review.
