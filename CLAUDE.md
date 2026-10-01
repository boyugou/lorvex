# CLAUDE.md — Lorvex

This repo holds the Apple-native Lorvex app and the schema, CloudKit, and
behavior-contract artifacts it owns. Read this first, then `apps/apple/CLAUDE.md`,
the app's operating manual.

```
apps/apple/      Apple-native, pure Swift.        → apps/apple/CLAUDE.md
schema/          SQLite schema — the app's authority, plus sync payload manifests.
cloudkit/        CloudKit record-type template/reference.
spec/            Behavior contract (docs + fixtures).
docs/            Project-level docs.               → docs/INDEX.md
plugins/lorvex/  Claude Code plugin: MCP launcher + skills. → plugins/lorvex/README.md
.claude-plugin/  Claude Code marketplace listing for plugins/lorvex.
```

The former cross-platform Tauri/React/Rust implementation was removed from this
tree on 2026-09-17. Its last in-tree state is the git tag `tauri-snapshot-final`;
its full history lives in `github.com/boyugou/ai-native-todo`. It is historical
context only, never a dependency or a behavioral oracle.

## Hard rules

1. **Pure Swift, no FFI, no second implementation in-tree.** The app runs on the
   pure-Swift `LorvexAppleCore` package (`apps/apple/core`) behind
   `SwiftLorvexCoreService`. Never add a Rust or web runtime, an FFI bridge, or
   cross-platform shims.
2. **`schema/schema.sql` is the schema authority.** The app realizes it
   byte-for-byte through its embedded copy
   (`apps/apple/Sources/LorvexCore/Resources/schema.sql`), governed by the embed
   check, migration ladder, and schema-freeze gate
   (`apps/apple/script/verify_schema_embed.sh`, `verify_migration_ladder.py`,
   `verify_schema_freeze.py`). Fix the schema here if it is genuinely wrong, then
   mirror the change into the embedded copy. The sync wire's field inventory is
   versioned independently in `schema/sync_payload/`: changing a known entity or
   field requires an explicit `payloadSchemaVersion` bump and the next
   contiguous manifest; released manifests are immutable.
3. **Contact routes through the lorvex.app support/privacy pages.** No email
   addresses anywhere.

## Where things are

- **Apple app** (`apps/apple`): SwiftPM package, `swift build`/`swift test` from
  that directory. Its operating manual is `apps/apple/CLAUDE.md`.

## The Swift core

The Apple app's backend is the pure-Swift `LorvexAppleCore` package. Its
current shape is described in the Core section of
`apps/apple/docs/architecture/apple-native-architecture.md`; why it is pure
Swift, what stays shared as language-neutral artifacts, and how the port was
sequenced are recorded in `docs/decisions/pure-swift-core-port.md`. Status and
remaining schema-backed gaps are tracked in `ROADMAP.md`. Read both before
extending the core: the boundary decisions in the record still hold.

## Subagents

Assign one bounded objective per subagent; the controlling session owns
acceptance review. Do not pin a model or reasoning setting in repository policy.
