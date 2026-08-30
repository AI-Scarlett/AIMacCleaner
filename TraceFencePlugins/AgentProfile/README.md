# TraceFence Agent Profile

Agent Profile is a first-party TraceFence plugin for generating a consistent
language, timezone, coarse-location, and proxy environment for supported Agent
launchers. It also compares direct and configured-proxy Google egress paths.

The plugin deliberately treats network-path validation and provider eligibility
as separate results. A changed IP, locale, or timezone does not prove that a
Google account is eligible for Antigravity. Google remains authoritative for
account, age, plan, organization, and associated-region checks.
