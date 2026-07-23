# Platform Capability Matrix
Canonical runtime/channel capability contract for current code and target product shape.

This matrix describes **peer runtimes with different capabilities**. It does **not** describe a primary-desktop / secondary-mobile hierarchy.

Use this document with:

- `app/src/lib/platform/platform.ts`
- `docs/design/ARCHITECTURE.md`
- `docs/design/DISTRIBUTION.md`

---

## Runtime Classes

The Tauri line has two runtime classes:

- **desktop runtime**
- **mobile runtime**

Windows and Linux are the product-facing Tauri desktop runtimes. The macOS
Tauri build remains a developer/reference desktop runtime for contributors who
only have a Mac. iOS, iPadOS, watchOS, visionOS, CloudKit/iCloud, App Intents,
and WidgetKit belong to the Swift app under `apps/apple`, not this Tauri
matrix. Android remains a future non-Apple mobile runtime.

---

## Current Code Contract

The current frontend contract exposes:

- `runtimeId`
- `runtimeClass`
- capability booleans
- `supportedSyncBackendKinds` for active sync backend availability
- `trayPresentationKind` for desktop shell presentation semantics
- adapter identity fields for native calendar / widgets / biometrics
- explicit native calendar support level (`active` vs `planned` vs `none`)

Low-level helpers such as `getDesktopPlatform()`, `getMobilePlatform()`, and `isMacRuntime()` may remain for runtime detection or narrowly scoped platform-family branching. The canonical app-level contract is now `runtimeId + runtimeClass + capabilities`.

### Current `RuntimeProfile` Field Coverage

This table is the exhaustive current-contract mapping for `app/src/lib/platform/platform.ts`.
It exists so the document can serve both as product/runtime guidance and as the
canonical interpretation of the current frontend capability contract.

| Field | Current Meaning | Canonical Interpretation |
|---|---|---|
| `runtimeId` | unified runtime identity | concrete runtime identity |
| `runtimeClass` | runtime class enum | desktop vs mobile runtime class |
| `supportsBiometricLock` | current biometric capability flag | runtime can expose biometric-protected surfaces today |
| `supportsMultipleWindows` | desktop-only UI shell flag | runtime can support multiple windows |
| `supportsTitleBarOverlay` | desktop UI shell flag | runtime can support title-bar overlay styling |
| `supportsMcpHosting` | desktop-only operator flag | runtime can host MCP locally |
| `supportedSyncBackendKinds` | current sync backend availability list | ordered set of active sync backends the runtime can select today |
| `trayPresentationKind` | desktop shell presentation enum | runtime exposes no tray surface, a menu bar extra, or a system tray icon |
| `supportsDesktopOverlays` | desktop shell flag | runtime can expose overlay-style desktop surfaces |
| `supportsAssistantCommandPolling` | desktop operator flag | runtime can support desktop assistant UI polling loop |
| `supportsAutostart` | desktop shell flag | runtime can register app autostart/login-item behavior |
| `supportsNativeCalendarRead` | current calendar capability flag | runtime can actively sync native calendar data today |
| `supportsBackgroundSync` | current background capability flag | runtime can actively run background sync loops today |
| `biometricAdapterKind` | biometric adapter identity | current biometric integration family (`touch_id`, `windows_hello`, `none`) |
| `nativeCalendarAdapterKind` | calendar adapter identity | current/planned native calendar adapter family |
| `nativeCalendarActivationState` | adapter activation state | whether native calendar support is `active`, `planned`, or `none` |

### Current Helper Exports

These exports remain intentionally outside `RuntimeProfile`:

| Helper | Current Meaning | Canonical Interpretation |
|---|---|---|
| `getDesktopPlatform()` | low-level desktop-family detection | implementation helper for platform-specific shell/runtime wiring |
| `getMobilePlatform()` | low-level mobile-family detection | implementation helper for runtime detection and bootstrap |
| `isMacRuntime()` | macOS runtime helper | narrow macOS branch for keyboard glyphs or shell affordances when capability flags are insufficient |

---

## Runtime / Channel Matrix

| Runtime/Channel | Runtime Class | Current Identity Fields | MCP Hosting | Standalone Product Goal | Current Status |
|---|---|---|---|---|---|
| macOS desktop | desktop | `runtimeId='macos'`, `runtimeClass='desktop'` | yes | developer/reference runtime for Mac-only contributors | active reference build |
| Windows desktop | desktop | `runtimeId='windows'`, `runtimeClass='desktop'` | yes | full desktop peer runtime | active |
| Linux desktop | desktop | `runtimeId='linux'`, `runtimeClass='desktop'` | yes | full desktop peer runtime | active (beta channel) |
| Android mobile runtime | mobile | `runtimeId='android'`, `runtimeClass='mobile'` | no | future reduced-capability but first-class mobile peer | planned |

### Interpretation rules

1. `runtimeClass='mobile'` means "future Android mobile runtime", not "Apple
   mobile runtime".
2. `supportsMcpHosting=false` on mobile does **not** imply "read-only product".
   It only means MCP hosting is unavailable there.
3. Desktop runtimes may expose extra operator surfaces. Future mobile runtimes
   must still be coherent standalone products.
4. A runtime may legitimately expose **zero active sync backends** today. That must be represented as an empty `supportedSyncBackendKinds` list, not coerced into a fake backend selection.

---

## Capability Matrix

`yes` means the capability is active in a currently active runtime.
`target yes` means it belongs in the target runtime shape, even if the runtime
or adapter is not fully activated yet.

| Capability | macOS reference | Windows | Linux | Android | Notes |
|---|---|---|---|---|---|
| Core app experience | yes | yes | yes | target yes | Today, Lists, Task Detail, capture, review, planning fundamentals |
| MCP hosting | yes | yes | yes | no | MCP is a desktop-capable operator surface |
| Multiple windows / overlays | yes | yes | yes | no | mobile uses reduced UI shape |
| Overlay title bar style | yes | no | no | no | current frontend contract uses a macOS-only shell flag |
| Desktop tray / menu bar | yes | yes | yes | no | desktop-only affordance |
| Desktop overlays | yes | yes | yes | no | overlay-style desktop surfaces such as floating/operator UI |
| Desktop assistant UI command polling | yes | yes | yes | no | desktop-only operator-loop capability |
| Desktop autostart | yes | yes | yes | no | login/startup registration capability |
| Native widgets | no | no | no | future platform-specific widgets | Apple WidgetKit belongs to `apps/apple` |
| Biometrics | yes | yes | target varies | target yes | Touch ID on macOS reference builds and Windows Hello on Windows are active; Android biometrics remain target capability |
| Filesystem bridge backend | yes | yes | yes | no direct path model | current backend, not the only future backend |
| Native calendar read | no | yes | yes | no active contract | provider-mirror only; the macOS reference build ships no native-calendar reader (EventKit belongs to `apps/apple`); Android needs an adapter kind, runtime profile, schema allowlists, and bridge before activation |
| Background sync | yes | yes | yes | target constrained | OS policy differs by runtime |

---

## Native Calendar Status

All runtimes follow the same rule:

> native calendar readers mirror into provider tables; they never write canonical synced event truth directly.

| Runtime | Provider Kind | Module / Adapter | Current Status | Target |
|---|---|---|---|---|
| macOS desktop reference | `none` | no native-calendar adapter (EventKit belongs to `apps/apple`) | none | Tauri macOS reference build ships no native-calendar reader |
| Windows desktop | `windows_appointments` | `platform::windows_calendar` | active | keep |
| Linux desktop | `linux_ics` | `platform::linux_calendar` | active | keep |
| Android mobile runtime | `none` | no native-calendar adapter contract yet | none | define adapter kind, runtime profile, schema allowlists, and Android bridge before activation |

---

## Distribution Channels

Canonical runtime/channel labels:

1. `macOS desktop`
2. `Windows desktop`
3. `Linux desktop`
4. `Android mobile runtime`

Distribution guidance and artifacts live in:

- `docs/design/DISTRIBUTION.md`

Release/distribution channels:

1. `GitHub Releases (macOS DMG)`
2. `GitHub Releases (Windows EXE)`
3. `GitHub Releases (Linux AppImage + .deb + .rpm)`
4. `Homebrew Cask`

Release artifact families covered by the current release workflow:

- `*.dmg`
- `*.exe`
- `*.AppImage`
- `*.deb`
- `*.rpm`

Do not add Apple store package artifacts, Apple store release tag triggers,
App Store Connect upload, or Apple mobile runtime artifacts to Tauri release
docs or automation. Those belong to the Swift app under `apps/apple`.

---

## Governance Rules

1. Any new field added to `RuntimeProfile` must be represented in the current-contract table above and, when user-meaningful, in the capability matrix below.
2. Any new runtime/channel introduced in distribution or release automation must be represented here.
3. Current-truth status and target-intent must be kept distinct. Do not mark a runtime as complete by describing target behavior in the status column.
