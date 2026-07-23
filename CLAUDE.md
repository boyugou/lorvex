# CLAUDE.md — Lorvex monorepo

This repo holds **two independent implementations** of Lorvex plus the artifacts
they share. Read this first, then the per-app `CLAUDE.md` for whichever app you
are working in.

```
apps/apple/   Apple-native, pure Swift.        → apps/apple/CLAUDE.md
apps/tauri/   Cross-platform Tauri/React/Rust.  → apps/tauri/CLAUDE.md
schema/       SQLite schema — the Apple app's authority; Tauri directionally aligned.
cloudkit/     Apple-owned CloudKit template/reference.
spec/         Cross-language behavior contract (docs + fixtures).
docs/         Project-level docs.               → docs/INDEX.md
```

## Hard rules

1. **Zero shared executable code, zero FFI between the two apps.** They agree
   through `schema/` and `spec/`; `cloudkit/` is Apple-owned template/reference
   material, not a Tauri contract. Never make `apps/apple` depend on
   `apps/tauri`'s crates, and never the reverse. The Apple app is pure Swift;
   the Rust crates under `apps/tauri` are a separate implementation, not an
   Apple dependency or behavioral oracle.
2. **`schema/schema.sql` is the Apple app's schema authority.** The Apple app
   realizes it byte-for-byte through its embedded copy
   (`apps/apple/Sources/LorvexCore/Resources/schema.sql`), governed by the
   Apple-only embed check, migration ladder, and schema-freeze gate
   (`apps/apple/script/verify_schema_embed.sh`, `verify_migration_ladder.py`,
   `verify_schema_freeze.py`). Apple and Tauri are **directionally aligned**
   through `spec/` concepts, **not** byte-locked: the Tauri schema copy may
   diverge freely and is never compared against `schema/`. Cross-platform data
   movement is AI-reconciled best-effort, not a lossless-by-construction
   interchange contract. Fix the schema here if it is genuinely wrong, then
   mirror the change into the Apple embedded copy. The Apple sync wire's field
   inventory is versioned independently in `schema/sync_payload/`: changing a
   known entity or field requires an explicit `payloadSchemaVersion` bump and
   the next contiguous manifest; released manifests are immutable.
3. **Each app builds, tests, and releases independently.** Do not introduce a
   build step in one app that requires the other.
4. **Contact routes through the lorvex.app support/privacy pages.** No email
   addresses anywhere.
5. **The Apple app runs on its pure-Swift core; never re-introduce a Rust FFI
   bridge.** The backend is `SwiftLorvexCoreService` over the `LorvexAppleCore`
   package (`apps/apple/core`). Shared behavior belongs in `schema/` and `spec/`.

## Where things are

- **Apple app** (`apps/apple`): SwiftPM package, `swift build`/`swift test` from
  that directory. Its operating manual is `apps/apple/CLAUDE.md`.
- **Tauri app** (`apps/tauri`): self-contained Cargo + npm + Tauri tree
  (snapshot of `github.com/boyugou/ai-native-todo`). Its operating manual is
  `apps/tauri/CLAUDE.md`. History lives in that origin repo.

## The Swift core

The Apple app's backend is the pure-Swift `LorvexAppleCore` package. The design,
the Swift-vs-shared split, and the parity strategy are in
`docs/superpowers/specs/pure-swift-core-and-monorepo-design.md`.
Status and remaining schema-backed gaps are tracked in `ROADMAP.md`. Read the
spec before extending the core — it is the source of truth for the boundary and
key decisions.

## Subagents

Assign one bounded objective per subagent; the controlling session owns
acceptance review. Do not pin a model or reasoning setting in repository policy.
