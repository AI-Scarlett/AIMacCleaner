# TraceFence Plugin Platform v2

## Product model

TraceFence is the host system and the application marketplace. A plugin is an
independently versioned application installed into that system. A plugin is not
a feature flag tied to the TraceFence release train.

The platform therefore tracks five independent versions or revisions:

| Value | Owner | Purpose | Forces a TraceFence update? |
| --- | --- | --- | --- |
| Host version | TraceFence app | Host features and security fixes | Yes |
| PluginKit ABI | Runtime SDK | Binary compatibility contract | Only when a plugin requires a newer ABI |
| Catalog revision | Store operations | Listings, prices, hashes and release pointers | No |
| Plugin version | Individual plugin | Plugin code and behavior | No, if compatible with the installed host and ABI |
| Entitlement revision | Commerce service | Purchase or subscription state | No |

`minimumHostVersion` is only a compatibility floor. It must never replace or
derive the plugin's own `version`.

## TraceFence 1.2.1 implementation verdict

The 1.2.1 implementation meets the first-party system-and-app model for signed,
same-Team-ID PluginKit v4 packages:

- the host, PluginKit ABI, catalog, entitlement and every plugin have independent
  version fields and update decisions;
- the signed catalog points to 45 immutable per-plugin releases owned by the
  TraceFence repository;
- acquisition, installation, activation and update state are represented
  separately;
- the package manager provides atomic install, enable/disable, one-version
  rollback, uninstall and data preservation;
- the runtime host lazy-loads compatible bundles and renders primary, component
  and settings surfaces through one coherent host presentation layer;
- Discover, Library and Updates separate browsing from ownership and lifecycle
  actions;
- package hash, catalog identity, Developer ID team, manifest, ABI, minimum host,
  minimum macOS and permissions are fail-closed gates.

Known boundaries remain deliberate: untrusted third-party plugins require a
future XPC isolation class, and individual paid SKUs require a unique commerce
product identifier for each plugin. TraceFence Standard currently grants the
first-party 45-plugin collection without coupling plugin updates to host updates.

## TraceFence 1.2.2 presentation correction

Version 1.2.2 separates plugin lifecycle management from daily use. The Store
no longer presents the runtime as a nested Settings sheet. Open requests dismiss
Settings and route through the application shell to My Plugins; pinned compact
panels also appear in the menu-bar Plugins tab. Both surfaces expose explicit
close actions and notify plugins when primary or component panels become visible
or hidden.

## TraceFence 1.2.3 surface contract

Version 1.2.3 makes placement and first-use behavior explicit catalog data. Each
plugin independently declares one desktop landing surface and an optional
menu-bar mode:

| Plugin shape | Desktop default | Menu-bar behavior |
| --- | --- | --- |
| Short action or live control | Quick control | Pinned quick control |
| Metrics, health or observation | Data panel | Compact status summary |
| Multi-section tool | Full workspace | Desktop only unless a separate compact control exists |
| Configuration-only integration | Settings | Desktop only |

The desktop host owns one bounded scrolling region beneath a fixed plugin
header. A plugin workspace that declares self-managed scrolling keeps that
responsibility; all other panels are wrapped by the host exactly once. The
menu-bar host never embeds a full chart or long-form workspace and always offers
a path back to the full desktop content when one exists.

## Target boundaries

### 1. Catalog

The catalog is immutable data. It contains listing metadata, the latest plugin
version, compatibility requirements, permissions, commerce offer references and
an immutable package artifact reference. It does not download, install, activate
or grant access.

### 2. Commerce

Commerce answers one question: may this account/device acquire and run this
plugin? Free, Standard, standalone purchase and enterprise grants all normalize
to one entitlement snapshot. Commerce does not infer installation or runtime
state.

### 3. Package manager

The package manager owns this filesystem contract:

```text
~/Library/Application Support/TraceFence/Plugins/
  Downloads/<plugin-id>/<version>/
  Staging/<transaction-id>/
  Installed/<plugin-id>/<version>.tracefenceplugin/
  State/<plugin-id>.json
  Previous/<plugin-id>/
  Data/<plugin-id>/
  Caches/<plugin-id>/
  Temporary/<plugin-id>/
```

It performs download, size/hash verification, safe extraction, manifest and ABI
validation, code-signing validation, atomic installation, active-version switch,
rollback and uninstall. It retains one previous known-good version. A native
bundle already loaded into the process is never claimed to be fully unloaded;
updates that cannot hot-switch are marked `restartRequired`.

### 4. Runtime host

The runtime host owns enable/disable, lazy loading, activation, health and UI
entry points. It activates a plugin only when the user opens it or explicitly
enables a declared background capability. Locked, disabled and merely installed
plugins have no timers, watchers or listeners.

The initial first-party compatibility runtime supports the pinned PluginKit v4
ABI and same-Team-ID packages. Future untrusted third-party plugins must run in a
separate XPC process; they do not enter the in-process trust class automatically.

### 5. Presentation

The marketplace UI consumes read-only snapshots from the four services above.
It never equates these different states:

- Owned
- Downloaded
- Installed
- Enabled
- Running
- Update available
- Restart required

The Store has three primary destinations:

- **Discover**: search, category, featured collections and plugin details;
- **Library**: owned and installed plugins, with Open, Enable, Settings,
  Rollback and Uninstall actions;
- **Updates**: only plugins with a newer compatible version, with per-plugin and
  update-all actions.

Plugin details show version history, download size, permissions, compatibility,
source/license attribution and release notes before purchase or install.

### 6. Use surfaces

The Store is not a plugin launcher. Purchase, installation, updates, rollback,
enable/disable and uninstall stay in the Store; normal plugin use is routed by
the application shell to one or more declared surfaces:

| Surface | Appropriate plugin shape | Host behavior |
| --- | --- | --- |
| My Plugins workspace | Every installed plugin | Persistent main-window destination with search, explicit close and plugin settings |
| Menu-bar quick panel | Short controls and live status | User-pinned tools only; opening the status item is sufficient for repeat use |
| Utility window | Long-running or multi-window workflows | Independently closable window restored by the host |
| Background service | Explicit background capability | Starts only after enablement and permission checks; no hidden activation from installation |

Existing PluginKit v4 `primaryPanel` and `componentPanel` capabilities are
eligible for the menu-bar quick panel and the workspace. Settings-only plugins
remain in the workspace. Future packages may add `presentation.window`,
`presentation.menu-bar`, or `runtime.background` capabilities without coupling
their version to TraceFence.

An Open action from Settings first dismisses Settings, then sends a launch
request to the application shell. Plugin UI must never be presented as a second
modal sheet above the Store. A workspace or utility window always exposes a
clear close action, while selecting another main navigation destination also
leaves the plugin surface.

## Package contract

Every package carries a manifest with at least:

```json
{
  "id": "clipboard-clear",
  "version": "1.0.10",
  "minimumHostVersion": "1.2.1",
  "minimumSystemVersion": "14.0",
  "pluginKitVersion": 4,
  "bundleRelativePath": "ClipboardClear.bundle",
  "factoryClass": "ClipboardClearPlugin.ClipboardClearPluginFactory",
  "capabilities": {
    "primaryPanel": true,
    "componentPanel": false,
    "settings": "none",
    "background": false
  },
  "permissions": []
}
```

The catalog ID may include the TraceFence namespace; the package ID is stable
inside the package. The package manager stores both and validates the explicit
mapping. IDs never change when ownership, price or version changes.

## Independent release train

The immutable public artifact convention is:

```text
tag: plugin-<plugin-id>-v<plugin-version>
asset: <plugin-id>-<plugin-version>.mactoolsplugin.zip
```

The `.mactoolsplugin.zip` suffix and `MacToolsPluginKit` binary name are retained
only for compatibility with the pinned PluginKit v4 bundles. Distribution,
catalog trust, update ownership and availability belong to TraceFence.

Updating one plugin creates one plugin release and a new signed catalog revision.
It does not bump the TraceFence app. A host update is required only if the new
plugin declares a higher host or PluginKit compatibility floor.

The initial migration may use a bootstrap batch internally, but production
catalog entries must point to immutable per-plugin release URLs before the
storefront is published.

## Compatibility policy

A plugin is installable only when all of the following are true:

1. the current entitlement permits acquisition;
2. the catalog signature and revision are valid;
3. macOS meets `minimumSystemVersion`;
4. TraceFence meets `minimumHostVersion`;
5. the host supports `pluginKitVersion`;
6. the package hash, identity and Team ID match the signed catalog;
7. the package manifest matches the catalog identity and version.

An incompatible plugin stays visible with an explanation. It is never silently
activated and it never forces an automatic TraceFence upgrade.

## Migration plan

1. Introduce independent platform state models and preserve existing catalog and
   commerce behavior behind adapters.
2. Replace the download-only service with an atomic package manager and active
   version records.
3. Embed the pinned PluginKit v4 compatibility framework and add a lazy runtime
   host for same-team first-party plugins.
4. Add a generic host surface for primary panels, component panels and settings.
5. Replace the vertical settings list with Discover, Library, Updates and a
   details sheet.
6. Move each production package to its own immutable release tag and URL.
7. Validate Clear Clipboard end to end: acquire, install, enable, open, perform
   the action, independently update, rollback, disable and uninstall.
8. Classify and test the remaining 44 plugins by permission and runtime risk.
9. Build TraceFence 1.2.1 only after the first loop is real and all visible
   unsupported states are fail-closed.

## Release gate evidence

Publication is allowed only after the Clear Clipboard acceptance loop passes in
the packaged TraceFence build. The 1.2.1 gate passed install, runtime load,
usable-surface detection, clipboard action, update, rollback, disable and
uninstall checks. Settings-only representatives also passed runtime and usable
surface checks. A source build, ZIP verification or upload alone still does not
count as usability evidence for future catalog revisions.
