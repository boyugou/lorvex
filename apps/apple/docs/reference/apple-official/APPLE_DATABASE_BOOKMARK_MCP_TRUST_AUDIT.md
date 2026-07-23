# Apple Database, Bookmark, and MCP Trust-Boundary Audit

> **Historical / removed capability.** The external-database picker,
> security-scoped database bookmarks, and database-bookmark switching this audit
> examines no longer exist. Storage is the single Lorvex-managed App-Group
> database resolved by the core's `DbLocator`; the only injection is the
> unsandboxed dev `LORVEX_APPLE_DB_PATH` override (resolved directly, never
> persisted or bookmarked), pinned by `ManagedStorageInvariantTests`. Kept for
> provenance: the App-Group container and MCP-helper trust-boundary analysis
> still describes the current shared managed-store boundary, but every bookmark /
> external-SQLite / atomic-cutover finding below refers to machinery that has
> since been removed.

This is a read-only audit of the macOS storage-authority system: managed App
Group storage, optional external SQLite files, security-scoped bookmarks,
in-process system surfaces, the bundled MCP helper, and their release
entitlements. It does not change product code.

Last verified: 2026-07-10 against repository `HEAD`
`605c8a6231605227334ab0f222a925b7f38a5aa5` and its clean working tree.

## Primary Apple Sources

- [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Security-scoped bookmark creation](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope)
- [Resolving bookmark data and replacing stale bookmarks](https://developer.apple.com/documentation/foundation/url/init%28resolvingbookmarkdata%3Aoptions%3Arelativeto%3Abookmarkdataisstale%3A%29-3ic6f)
- [User-selected read/write entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Accessing App Group containers in an existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
- [Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)

Apple's current App Group documentation is especially relevant on macOS 15 and
later: group containers are protected from processes outside the authorized
group. That makes the helper's ability to exercise its own App Group entitlement
on behalf of an arbitrary stdio parent a real authority boundary, not merely an
alternate path to an otherwise world-readable file.

## Architecture That Is Already Sound

- The main app and helper share the managed database through a provisioned App
  Group, rather than a path guessed from another process's container.
- `AppGroupAccess` verifies the running process's actual App Group entitlement
  with Security framework APIs and requires a stable signing team identifier.
- `SecurityScopedResourceAccess` holds `startAccessingSecurityScopedResource()`
  for the lifetime of the core service and releases it on deinitialization.
- `DatabaseSelectionResolver` follows Apple's stale-bookmark contract: use the
  successfully resolved URL, create replacement bookmark data, and persist the
  replacement. An unresolvable bookmark does not fall through to an unsafe raw
  path.
- A failed bookmark resolution falls back to managed storage with a blocking
  user-facing notice instead of silently presenting an unexplained empty app.
- Runtime-factory cache keys include device/inode identity for scoped files, so
  replacement at the same pathname can produce a new service.
- Factory reset and managed-store replacement close cached services, coordinate
  through the storage-generation protocol, and preserve SQLite sidecar
  correctness.
- The MCP self-probe removes inherited database override variables, launches the
  actual packaged helper, bounds execution time, and performs a real store read.

These are important strengths. The findings below are composition failures
around those primitives, not evidence that the primitives themselves are all
wrong.

## Storage Authority Matrix

| Caller | Current authority decision | Important consequence |
| --- | --- | --- |
| Main macOS app | `AppCoreFactory.make`; sandboxed process is forced to managed storage | Correct intended MAS policy |
| App Intents, notification actions, Spotlight, widget-style in-process surfaces | `LorvexCoreRuntimeFactory` → `AppDatabaseResolver`; reads persisted bookmark/path with no sandbox gate | Can disagree with the main app |
| Sandboxed MCP helper | Managed App Group store unless environment supplies an override; external override is rejected/unreachable | Correct intended packaged-helper policy |
| Unsandboxed MCP helper | Environment path/bookmark from Settings | Tracks external selection only when generated environment stays coherent |
| Settings UI | Persists a new path/bookmark immediately; main store changes only after “Apply Runtime” | Creates a two-phase cutover window |

## Findings

### D1 — HIGH: the sandbox managed-store gate is absent from system-surface resolution

`AppCoreFactory.make` explicitly ignores every external selection when
`settings.isSandboxed`. `LorvexAppleBootstrap`, however, always installs
`AppDatabaseResolver.resolveSelectedLocation` as the runtime factory's selected
database provider. That resolver has no sandbox check and honors a persisted
bookmark or raw path.

Therefore a sandboxed main app can be on the managed App Group database while an
App Intent, notification action, or another factory-created surface in the same
process opens the persisted external database. The main app carries the
user-selected-file and app-scoped-bookmark entitlements, so a valid bookmark can
work in that process even though the separately signed MCP helper remains on the
managed database.

This is most likely after a distribution-policy transition, restored defaults,
development seeding, or any other case where an old external selection remains
persisted. The existing sandbox regression tests cover `AppCoreFactory` only;
they do not call `makeForAppIntent`, `makeForNotification`, or the installed
provider.

The durable fix is one storage-authority resolver that returns the effective
selection for every surface, including the sandbox policy. A release test should
seed a valid external bookmark, mark the process sandboxed, construct the main
core plus every factory surface, and prove that every one resolves the same
managed database identity.

### D2 — HIGH: selecting or clearing an external database is not an atomic cutover

The file importer calls `settings.selectDatabaseFile(url)`, which immediately
writes `databasePath` and `databaseBookmarkData` to defaults. The running
`AppStore.core` remains on the old database until the user separately chooses
“Apply Runtime.” Clearing the path has the same split in reverse.

During that interval:

- `AppDatabaseResolver` reads the new persisted selection immediately;
- the next App Intent or notification action can open and mutate the new store;
- Settings-generated MCP configuration also reflects the new selection;
- the visible main app and its existing detached windows still use the old core.

The runtime factory's identity-keyed cache correctly reacts to a changed
provider, but that makes the split real sooner; it does not make the selection
transactional. This primarily affects the unsandboxed external-storage workflow
because the current sandboxed UI disables selection.

Stage the candidate selection separately, preflight it, then perform one cutover
operation that closes/invalidate old services, swaps the main core, and only
then commits the effective selection. On failure, retain both the old settings
and the old core. “Apply Runtime” should not be a second manual commit button for
a setting that other writers already observe.

### D3 — HIGH: the independently launchable MCP helper has no client authentication

The helper accepts MCP over stdin/stdout and opens the managed App Group store
when launched with no database configuration. It does not require a pairing
secret, signed client identity, per-client capability, approval session, or
revocable token. Any local process that can execute the bundled inner binary and
speak the protocol can ask the helper to exercise its App Group entitlement.

The exposed catalog is broad: it reads private tasks, memory, reviews,
preferences, audit data, and calendars; it also performs writes, archive/delete
operations, preference changes, and data export. Individual destructive tools
have useful safeguards — for example, permanent task deletion requires an
archive-first sequence — but those guards do not authenticate the caller or
prevent bulk disclosure and mutation.

This is a classic confused-deputy boundary: macOS 15+ can deny an unrelated
process direct access to the App Group container, while the same process can
launch the authorized helper and request the data over stdio. The Settings copy
correctly says to configure only trusted assistants, but trust guidance is not
an enforcement mechanism.

Before release, define the threat model explicitly. At minimum, consider a
per-install, revocable pairing capability and make the helper fail closed when
it is absent. A plaintext token copied into a third-party config is still a
bearer capability, but it creates revocation and accidental-launch boundaries
that do not exist today. Stronger designs can add client-specific grants,
read-only versus write scopes, expiry, visible active-client state, and a user
approval step for destructive/export operations.

### D4 — MEDIUM-HIGH release gate: the MCP packaging model intentionally differs from Apple's standard embedded-tool recipe

Apple's current guide for a command-line helper embedded in a sandboxed app
instructs the helper to carry only `com.apple.security.app-sandbox` and
`com.apple.security.inherit`. Lorvex instead packages the executable inside a
nested background `.app` and signs it with its own sandbox plus App Group
entitlement, because an external AI client — not the Lorvex parent app — launches
it and it needs independent access to the managed database.

That difference is understandable and may be necessary for this product, but it
is not proven by applying the standard inherited-helper recipe. Treat the nested
app as a separately provisioned executable product:

- verify its explicit App ID and provisioning-profile authorization;
- inspect the final inner executable and nested app entitlements after export;
- install the exact App Store-exported package and launch the inner binary from
  each supported client;
- run App Store validation/Transporter early enough to change architecture if
  the nested independently entitled helper is rejected;
- confirm update, bundle relocation, and uninstall behavior.

Do not “fix” this mechanically by adding `com.apple.security.inherit`: when an
external client is the parent, inherited sandbox authority may be the client's,
not Lorvex's, and can destroy the intended App Group access model.

### D5 — MEDIUM-HIGH: an undocumented environment variable chooses the storage policy

`AppSandboxEnvironment` treats a nonempty `APP_SANDBOX_CONTAINER_ID` environment
variable as authoritative. Apple's public guidance describes verifying the
sandbox through the signed entitlement, `codesign`, or Activity Monitor; this
audit found no Apple API contract promising that this environment variable is a
stable application-facing signal.

The kernel still enforces the actual sandbox, so spoofing this variable does not
grant file access. The risk is correctness: an absent or unexpected signal can
select the external-storage code path while the process is actually sandboxed,
or a supplied variable can force managed-only behavior in an unsandboxed run.
That affects the main core, MCP environment generation, helper diagnostics, and
the Settings UI.

Use the actual `com.apple.security.app-sandbox` entitlement as the production
authority, with an injected test seam. `AppGroupAccess` already demonstrates the
Security-framework pattern in this repository. The final signed-archive test
should compare that result to observed runtime behavior rather than asserting
only synthetic environment dictionaries.

### D6 — MEDIUM: “Choose External Storage” can rename an arbitrary `.data` file and replace it with a fresh database

The picker accepts `.database`, `.sqliteDatabaseFile`, and the very broad
`.data` type. Selection persists the bookmark without a read-only SQLite/header
or Lorvex schema preflight. When the selected file is later opened, the store's
recovery policy treats “not a database,” corruption, or missing Lorvex schema
bookkeeping as recoverable: it renames the original alongside the path as an
`incompatible-….bak` file and creates a new Lorvex database at the selected
pathname.

The recovery code preserves the bytes and the UI later surfaces the backup
location, so this is not silent deletion. It is still a surprising mutation of
a user-selected arbitrary file, especially because the user guide describes the
choice as an existing Lorvex SQLite file.

Preflight before committing the bookmark: reject directories and unexpected
file types, inspect SQLite identity and Lorvex schema bookkeeping read-only, and
show a specific confirmation before any quarantine/replacement. Define symlink,
hard-link, package, network volume, and cloud-synced-folder policy explicitly.

### D7 — MEDIUM: stale bookmarks have two incompatible policies inside Settings

`DatabaseSelectionResolver` correctly uses and re-mints a stale bookmark.
`AppSettingsStore.resolvedBookmarkedDatabaseURL`, which feeds Finder reveal and
MCP environment generation, instead treats the same successfully resolved stale
bookmark as unusable and returns `nil`.

Normally the launch factory heals staleness first. If a bookmark becomes stale
during a running session, however, the app can retain/use its external store
while Settings emits no bookmark/path override and the unsandboxed helper falls
back to managed storage. A single resolver/result type should serve app open,
system surfaces, display/reveal, and MCP configuration.

### D8 — LOW-MEDIUM: failed scope activation is represented as successful resolution

`SecurityScopedResourceAccess` records the Boolean returned by
`startAccessingSecurityScopedResource()`, but callers cannot inspect it.
`DatabaseSelectionResolver` returns `.bookmarked` even when access was not
started. The later SQLite open will usually fail rather than bypass the sandbox,
so this is not a privilege escalation. It does delay the error and makes the
resolution state misleading. Make activation failure an explicit resolution
case and keep fallback fail-closed.

### D9 — LOW-MEDIUM documentation drift: installation path does not determine sandboxing

Several setup/user documents say that a signed app, a notarized app, or
“anything under `/Applications`” is sandboxed. The sandbox is determined by the
signed `com.apple.security.app-sandbox` entitlement, not the folder containing
the bundle; notarization and Developer ID signing do not inherently add it.

This wording can cause support engineers and users to choose the wrong database
contract. Describe exact release channels/artifacts and instruct diagnostics to
inspect the signed helper entitlement.

## Release Decisions to Freeze

1. Decide whether external databases are a supported Developer ID feature or a
   development/support-only tool. They are currently unavailable in a sandboxed
   release even though MAS app entitlements still advertise user-selected
   read/write and app-scoped bookmarks.
2. If MAS is managed-only, either remove those unused file entitlements from the
   MAS target or document the other feature that requires them. Least privilege
   is easier to review and maintain.
3. Define the MCP caller-authentication and revocation model before public user
   data sits behind the helper.
4. Make database selection one atomic, observable authority transition across
   main app, system surfaces, detached windows, CloudKit coordinator, and helper.
5. Preserve the managed-store generation/cutover protocol and the existing
   bookmark re-mint behavior while unifying the policy.

## Required Evidence

- Exact signed MAS and Developer ID archives, with entitlements and embedded
  profiles dumped for the main app, MCP nested app/inner executable, and widget.
- Cold/warm launch matrix with a seeded external bookmark, stale bookmark,
  deleted file, replaced inode, denied scope, and old defaults.
- A test that performs selection/clear while concurrently invoking every system
  writer and proves all writes land in one database.
- Hostile-local-client MCP tests: no configuration, wrong/revoked token,
  read-only grant, destructive/export grant, process crash, and copied-config
  leakage.
- MAS-installed helper launch from each supported assistant, not merely the
  in-app self-probe.

