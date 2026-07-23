# spec/ — shared behavior contract

Language-neutral specifications and test vectors for behavior that must stay
stable across Lorvex implementations. Apple Swift is the canonical
implementation for product behavior; this directory records the shared boundary
so companion implementations can follow it without becoming an oracle for Apple.

Intended contents:

- **Behavior docs** (`*.md`) — recurrence rules (`RECURRENCE.md`), the data
  export format (`EXPORT_FORMAT.md`), sync-envelope format, canonical JSON,
  timezone/DST resolution, the `ai_changelog` contract, the data model.
- **`fixtures/*.json`** — concrete input/output vectors an implementation's test
  suite can load and assert against. The `canonical_json` vectors pin the exact
  canonical bytes Apple's sync checksums are computed over, so Apple's own byte
  format can't drift across releases; a companion implementation aligns on the
  same *semantics* rather than byte-locking to them.

## Two kinds of cross-implementation data movement

These are different contracts and must not be conflated:

- **Byte-canonical sync.** Apple's own sync checksums depend on an exact
  canonical byte format (the recurrence rule in `RECURRENCE.md`, the
  `canonical-json` fixtures). This form is byte-locked *for Apple's own producer*
  so it can't drift across Apple releases. A companion implementation converges
  to the same *semantics*; nothing byte-locks the two runtimes to each other.
- **Semantic data export.** The user-facing data export (`EXPORT_FORMAT.md`, the
  `export_data` MCP tool) is an **AI-reconciled best-effort document for
  cross-tool migration** — meaningful entities and fields, with sync/replication
  internals dropped. It is deliberately **not** lossless and **not** byte-parity:
  moving data across implementations reconciles semantics, it does not replay a
  change log or reproduce byte-identical rows.

Apple Swift is the canonical product surface for both. The Tauri implementation
is directionally aligned to these concepts, not byte-locked to them.

## Current contract mechanism

This directory is the home for language-neutral contracts. The current
cross-implementation contract is maintained two ways:

- **Schema** — `schema/schema.sql` is the Apple app's schema authority, kept
  byte-identical to the Apple embed by `apps/apple/script/verify_schema_embed.sh`.
  Tauri is only directionally aligned to the concepts here, not byte-locked to the
  schema; cross-platform data transfer is AI-reconciled best-effort.
- **Behavior** — shared specs in this directory define cross-implementation
  contracts; Apple locks canonical product behavior in its test suites, and
  companion implementations should converge to those contracts.

The `canonical_json` fixtures pin the exact canonical byte format Apple's own
sync checksums depend on, so Apple's producer can't drift across releases. Add a
`fixtures/` entry and a loader when a specific behavior contract needs a concrete
vector to assert against.

Historical parity plans remain under `docs/superpowers/specs/`; treat them as
context, not as the current authority model.
