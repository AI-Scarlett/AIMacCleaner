// The DiskClean test suite historically imports the host module for integration visibility, but
// its safety logic is intentionally host-independent. A tiny focused-test module keeps those
// imports valid without launching the complete app or linking every unrelated plugin.
enum DiskCleanHostTestShim {}
