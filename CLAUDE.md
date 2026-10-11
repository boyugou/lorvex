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
2. **`schema/` is the schema authority.** `schema/schema.sql` is the version-1
   baseline and `schema/migrations/` the numbered ladder after it. The app
   realizes both byte-for-byte through its embedded copies
   (`apps/apple/Sources/LorvexCore/Resources/schema.sql` and `Migrations/`),
   governed by the embed check, migration ladder, and schema-freeze gate
   (`apps/apple/script/verify_schema_embed.sh`, `verify_migration_ladder.py`,
   `verify_schema_freeze.py`). The freeze is armed
   (`schema/migration_policy.json` has `launched: true`): a schema change is a
   new numbered migration in `schema/migrations/`, mirrored into the embedded
   copy, and `schema.sql` and released migrations are never edited. The sync
   wire's field inventory is versioned independently in `schema/sync_payload/`:
   changing a known entity or field requires an explicit `payloadSchemaVersion`
   bump and the next contiguous manifest; released manifests are immutable.
3. **Contact routes through the lorvex.app support/privacy pages.** No email
   addresses anywhere.

## Repository and privacy

This repository (`github.com/boyugou/lorvex`) is public and is the only
working repository: every tracked file is published when it is pushed.

- Never commit credentials, signing material, email addresses, a personal
  name in a signing identity, or a developer machine's paths. The static gate
  `apps/apple/script/verify_public_safety.py` rejects them; run
  `apps/apple/script/verify_static_gates.sh` before pushing.
- Local-only files (`secrets/`, `CLAUDE.local.md`, tool state, build and
  capture output) are listed in `.gitignore`; add any new kind there.
- Commit with a GitHub noreply address.
- Setting up a machine, the local files a clone lacks, and the release steps:
  `docs/development/NEW_MACHINE.md`. Open work: `ROADMAP.md`.

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
