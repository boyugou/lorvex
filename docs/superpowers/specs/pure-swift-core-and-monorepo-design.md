# Lorvex: Pure-Swift Core Port + Monorepo — Design Spec

**Status:** Shipped. The monorepo merge (Phase 0) and the pure-Swift core
(Phases 1–5) have landed; the Apple app runs end-to-end on the pure-Swift
`LorvexAppleCore` package with no Rust FFI. This document is the design record
for the Swift-vs-shared boundary and the key decisions behind it; current status
by lane lives in `ROADMAP.md`.
**Repo:** the existing `lorvex` repo, restructured in place as the monorepo.

---

## 1. Goal and end state

Two intertwined objectives:

1. **Make the Apple app pure Swift.** The port started from an Apple app whose
   every backend operation routed through `rust-bridge/` (an FFI dylib, ~12k
   lines) fronting the Rust core crates. The shipped end state has **no
   `rust-bridge/`, no FFI, no Rust dependency** in the Apple app — the domain
   logic, SQLite store, workflow executor, and CloudKit sync are all native
   Swift.

2. **Merge into one monorepo** containing both products — the cross-platform
   Tauri/React desktop app and the Apple-native Swift app — so that genuinely
   shared artifacts live in one place and cannot drift, while everything
   executable stays fully independent (zero shared code, zero FFI between them).

### Sequencing decision: merge first, then port

**Merge the monorepo first; port the Swift core second.** This is acceptable
because temporarily breaking the Apple app's usability is explicitly OK — the
Apple app does **not** build/run during the port (months, not days), and that is
an accepted cost.

Rationale for this order:

- The shared artifacts (`schema/`, `spec/`, `cloudkit/`) become authoritative
  immediately — the core anti-drift goal — rather than after a months-long port.
- The Swift port then happens *inside* the clean `apps/apple/` structure, against
  the shared `schema.sql` and `spec/fixtures/` from day one. No porting against
  the old layout and re-moving everything at merge time.
- The Rust crates stay inside the self-contained Tauri tree (`apps/tauri/`). The
  port harness generates parity fixtures *from* those crates at test time — giving the port a
  free reference oracle **without** `rust-bridge` ever being an FFI dependency of
  `apps/apple`. So: "no FFI in the Apple app" AND keep the oracle.
- A unified tree gives a **global vantage point**: with both apps and the shared
  artifacts side by side, it is far easier to reason about what is genuinely
  shared, what each side implements, and where the two must agree — which in turn
  sharpens every later port decision.

At merge, `rust-bridge/` is **deleted** from the Apple tree and the core backend
targets (`LorvexDomain/Store/Workflow/Sync/Runtime`) start as stubs that compile
but are non-functional; the port fills them in. Pure-Swift is the target end
state, reached through a verifiable transition.

---

## 2. Final architecture: what is Swift, what is shared

### 2.1 Pure-Swift (Apple app, `apps/apple/` at merge time)

Everything executable in the Apple app is native Swift. New core targets to be
ported from the Rust crates:

| New Swift target | Ported from (Rust) | Responsibility |
|---|---|---|
| `LorvexDomain` | `lorvex-domain` | Value types, validation, RRULE recurrence, DST, HLC, canonical JSON. Pure, I/O-free. |
| `LorvexStore` | `lorvex-store` | SQLite over the **shared** `schema.sql` (66 tables, 17 triggers, FTS5). GRDB.swift. |
| `LorvexWorkflow` | `lorvex-workflow` | Mutation executor, `ai_changelog` audit, idempotency. |
| `LorvexSync` | `lorvex-sync` (+ `-sync-payload`) | CloudKit envelope, conflict resolution, tombstones, apply cycles. |
| `LorvexRuntime` | `lorvex-runtime` | DB locator, device identity. |

Existing Swift targets (`LorvexCore`, `LorvexMCPHost`, all UI/widget/watch/CarPlay
targets) remain; `LorvexCore.LorvexCoreServicing` stays the single write contract
and gets re-backed by the pure-Swift stack at cutover. `rust-bridge/` is deleted.

### 2.2 Shared with Tauri (language-neutral artifacts only — NOT code)

Three explicit shared surfaces. No shared Rust crate, no shared Swift module, no
FFI. The two apps agree by conforming to the same artifacts, verified in CI.

| Shared artifact | Single authority | How each side consumes it |
|---|---|---|
| `schema/schema.sql` | root copy, the **Apple app's** schema authority | The Apple app realizes it byte-for-byte through its embedded copy, gated by Apple-only checks (`verify_schema_embed.sh`, migration ladder, schema freeze). Tauri keeps embedding its own in-tree copy, which is **directionally aligned** via `spec/` concepts and may diverge freely — there is no cross-runtime parity gate. |
| `cloudkit/` (record-type template + deploy script) | one `.ckdb` template, parameterized container ID | Each app deploys to its **own** container (see open question §6). |
| `spec/` (behavior docs + `fixtures/*.json`) | hand-authored (port-era fixtures were generated from Rust test cases) | The cross-app behavior contract: both apps conform to the documented concepts and fixtures. Tauri is **not** a behavioral oracle for Apple work; the Apple implementation is the canonical product surface, and `spec/` is where genuinely shared behavior is recorded. |

**Repo layout.** `apps/tauri/` holds the entire current `lorvex_cc` tree
unchanged (its own Cargo workspace + npm workspace + Tauri backend + crates +
`mcp-server` + `shared` + `skill`) — self-contained, builds with near-zero path
rewrites. `apps/apple/` holds the Swift package. Only `schema/`, `cloudkit/`,
`spec/` (and project-level `docs/`) live at root. Crates are **not** hoisted to a
root `crates/`: they are Tauri's, the Apple app never imports them, so nesting
them in `apps/tauri/` is both lower-risk and more honest about ownership.

**Schema authority is Apple-owned.** The root `schema/schema.sql` and the Apple
embedded copy are byte-locked to each other by the Apple-only embed check; the
Tauri copy is directionally aligned and may diverge. Port *scope* (how many ops
the Swift workflow implements) and schema *coverage* are independent axes — the
Apple app applies the full 66-table schema verbatim and leaves unused tables
empty.

**License to fix the schema.** The `schema.sql` is authoritative, not sacred, and
it is the Apple app's schema authority. If it has real defects (missing index,
wrong constraint, denormalization bug), fix it in the shared artifact — but
conservatively — then mirror the change into the Apple embedded copy and
re-validate. Apple and Tauri are only directionally aligned via `spec/`, not
byte-locked, so the Tauri copy tracks it best-effort and may diverge. Schema
changes are Phase 2+ work, never silent.

---

## 3. The parity harness (spine of every port phase)

The risk in a faithful port is silent behavioral drift. Mitigation: the Rust core
already has extensive `#[test]` coverage. We extract those cases into
language-neutral JSON fixtures under `spec/fixtures/` and run the Swift port
against the identical inputs/outputs.

- A Rust test-binary (or `#[test]` with a dump mode) emits fixtures:
  recurrence expansions, DST resolutions, HLC orderings, `canonical_json`
  byte-output, validation accept/reject cases, envelope encodings.
- Swift tests load the same files and assert identical results.
- `canonical_json` gets **byte-equality** assertions specifically — sync
  checksums in Phase 4 depend on Rust and Swift producing identical canonical
  bytes for the same logical value.

During the port, `rust-bridge` additionally served as a live oracle — the same
operation run through both backends with outputs diffed. That role ended at
cutover: the bridge is deleted, and the Rust crates are not an oracle for
current Apple work.

---

## 4. Phased execution

Merge first; then port. After the merge the Apple app is intentionally
non-functional at the core layer until the port restores it.

```
Phase 0  Monorepo merge   restructure lorvex in place: Apple tree -> apps/
                          apple (delete rust-bridge); import lorvex_cc snapshot ->
                          apps/tauri (self-contained, crates nested); hoist
                          schema/ cloudkit/ spec/ to root; root README/CLAUDE/
                          ROADMAP/LICENSE/.gitignore. Acceptance: `swift package
                          describe` resolves in apps/apple, `cargo metadata`
                          resolves in apps/tauri, shared dirs authoritative.
                          Real CI workflows + cc end-to-end build deferred.
Phase 1  LorvexDomain     pure value types, validation, recurrence, DST, HLC,
                          canonical_json. No I/O. Fixture parity vs crates/.
Phase 2  LorvexStore      SQLite over shared schema/schema.sql. GRDB.swift.
                          Schema-parity (SHA) test + repository read/write parity.
Phase 3  LorvexWorkflow   mutation executor, ai_changelog audit, idempotency.
Phase 4  LorvexSync       CloudKit envelope, conflict resolution, tombstones.
Phase 5  Cutover          re-back LorvexCoreServicing with pure Swift; the 63
                          dependent files become functional again. App restored.
```

### Phase 0 decisions (settled)

- **Target repo:** the existing `lorvex` repo, restructured in place;
  remote stays `lorvex.git`. It becomes the canonical monorepo.
- **Tauri import = snapshot, not subtree.** `lorvex_cc` (GitHub
  `ai-native-todo`) is copied as a working-tree snapshot (excluding `.git`,
  `target/`, `node_modules/`, `dist/`); its history stays in the original repo,
  referenced by a pointer in `apps/tauri/README.md`. Avoids grafting a huge
  dual-root history into `lorvex`.
- **`rust-bridge/` deleted** from the Apple tree at merge. The Rust crates under
  `crates/` remain and serve only as the port's fixture-generation oracle — never
  an `apps/apple` dependency.
- **`lorvex_original/` discarded** — stale duplicate of `lorvex_cc`.
- **All Phase-0 work happens on a branch** (`monorepo-merge`), not `main`, so the
  restructure is reviewable and revertible.

---

## 5. Phase 1 detail — `LorvexDomain`

**Purpose.** Pure, I/O-free Swift library reproducing `lorvex-domain` (~12,000
non-test lines, 42 modules). All `Sendable` value types. No SQLite, no CloudKit,
no nondeterministic Foundation APIs. Builds and tests in isolation;
**nothing wires into the live app in Phase 1.**

**Lands as.** A **standalone SwiftPM package** at `apps/apple/core/`
(`LorvexAppleCore`), holding `LorvexDomain` (and later Store/Workflow/Sync/
Runtime) + their tests, with zero dependency on the app layer. Kept separate so
the port builds and tests in isolation (`cd apps/apple/core && swift test`,
~instant) while the app is mid-migration and does not fully compile across all
platforms via plain `swift test`. The app package (`apps/apple/Package.swift`)
consumes these products via a local path dependency at cutover.

**Port order** (dependency depth; each cluster validated before the next):

1. **Primitives** — `entity_id`, `ids`, `version`, `canonical_json`,
   `text_sanitize`, `unicode_hygiene`, `content_limits`, `naming`. Leaf
   utilities. `canonical_json` is load-bearing (byte-identical to Rust).
2. **Time & HLC** — `time`, `dst`, `hlc`, `hlc_state`, `hlc_session`,
   `hlc_observer`. The hybrid logical clock — ordering authority for sync.
3. **Recurrence** — `recurrence`. RRULE expansion × DST.
4. **Entities & validation** — task/list/calendar/`habits`/`memory`/
   (~1.8k lines), `status_transition`, `attendee_status`.
5. **Supporting** — `calendar_ics`, `query`, `merge`, `capability`,
   `preference_keys`, `provider_kind`, `provider_link`, `feedback`,
   `diagnostics`.

**Parity.** Each cluster ships with fixtures extracted from the corresponding
Rust tests; Swift tests assert identical results. `canonical_json` byte-equality
is a hard gate before Phase 4.

**Out of scope for Phase 1.** SQLite (P2), mutation/audit (P3), CloudKit wire
format (P4). The HLC and `canonical_json` ports done here are exactly what P4
consumes.

---

## 6. Open questions (resolve at the relevant phase)

- **Superseded CloudKit container question (Phase 4):** this historical note
  predated the current platform split. CloudKit/iCloud now belongs only to the
  Apple Swift app. Tauri must use non-Apple sync providers for Windows/Linux
  and any future Android runtime, with cross-ecosystem movement handled by
  export/import or a future provider-neutral sync design.
- **GRDB vs alternatives (Phase 2):** GRDB.swift is the strong default (mature,
  FTS5, migrations, Sendable-friendly). Confirm before Phase 2.
- **Fixture extraction mechanism (Phase 1):** dedicated Rust dump binary vs
  annotating existing tests. Decide during Phase 1 planning.

---

## 7. Non-goals

- No shared executable code or FFI between the two apps — ever.
- No second copy of the schema (no `apps/apple/schema.sql`).
- No `lorvex_original/` snapshot fork carried forward.
- No big-bang "port + merge simultaneously."
- Contact routes through the lorvex.app support/privacy pages only — no email
  addresses anywhere (CLAUDE.md rule).
