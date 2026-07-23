# Apple Polish — Evidence-Backed Backlog

Open, verified, code-level findings with `file:line` evidence — the actionable
companion to `UX_POLISH_LOG.md` (which holds decisions + rationale). Each item is
either confirmed-open against current code or marked with its verification state.
When an item is fixed, move a one-line decision+rationale entry to
`UX_POLISH_LOG.md` and delete it here.

Status legend: `OPEN` (verified present) · `FIXING` (in progress this session) ·
`FIXED` (landed; pending prune) · `NEEDS-VERIFY` (claimed but unconfirmed) ·
`FEATURE` (real but larger than a one-commit fix).

---

## macOS (LorvexApple)

No open macOS items right now.

## iOS / iPadOS (LorvexMobile)

### IOS-3 — `OPEN` — Habit rows show today's progress but no persistent streak
Severity: MEDIUM (value; small fix). `MobileHabitRow.habitSummary`
(`Sources/LorvexMobile/MobileStoreHabitSection.swift:201-218`) shows
`habit.todayProgressText` (e.g. "0/1 today") and, only when
`habit.showsMilestoneStrip` is true, a `MobileHabitMilestoneProgressView`. The
milestone strip is conditional (near a milestone threshold); there is no
always-visible streak number (e.g. "🔥 6") on the row or in habit detail.
Streaks are the core motivator of habit tracking. Completion history is
already stored (`MobileHabitPresentation`, `MobileHabitDisplayText` already
format streak text for the milestone strip) — this is presentation reuse, not
new data plumbing.

### IOS-4 — `NEEDS-VERIFY` — Tasks list divider inconsistency
Severity: LOW (visual). Design-review finding: one row divider in the Tasks
list renders full-width from the leading edge where the rest are inset past
the priority ring. Needs on-device confirmation against
`MobileActionTaskRow`/the Tasks list grouping before deciding whether it marks
an intended group boundary (leave) or is an inconsistency (normalize the
inset).

### IOS-5 — `NEEDS-VERIFY` — Debug launch-nav hook may apply before the nav stack mounts
Severity: LOW (debug/QA-only). `debugApplyLaunchNavigationIfNeeded()`
(`Sources/LorvexMobile/MobileStoreDebugSeed.swift:208`) mutates
`selectedTab`/sheet-presentation state right after `store.refresh()` in
`LorvexMobileApp.swift`, before SwiftUI is guaranteed to have mounted the nav
stack. Design-review finding: a `lorvex://firsttask`-style hook can land on
the tab root instead of pushing the task detail. Needs on-device confirmation;
if reproduced, defer the push until the stack exists so detail screens are
screenshot-able for QA.

### IOS-6 — `OPEN` — Today empty/all-done states and exploratory ideas
Severity: LOW-MEDIUM; mostly exploratory. From the iOS design review:
- Verify and polish the Today screen for the no-open-tasks state (fresh
  install / cleared day) and the all-tasks-complete state — an "all done"
  celebration beats an empty list. No Today-specific empty/celebration state
  was found in `MobileStoreTodayView`/`MobileStoreTodayRegularView`. Same
  question for the Tasks per-filter empty states (Someday/Completed/Cancelled).
- Exploratory, lower priority: a navigable Today date range or a lightweight
  "week ahead" peek; using the More tab's empty space for an at-a-glance
  stats strip (tasks completed, habit adherence, review streak) — optional,
  sparse is also a valid choice.
- Verify VoiceOver labels and Dynamic Type at the largest sizes for the
  week-view prev/next chevrons and the habit completion rings; confirm task
  rows expose complete/defer/focus as swipe actions, not only the detail
  sheet.

## Localization

### L10N-1 — `IN PROGRESS` (background) — Expand Swift locale coverage (13 → 27)
Swift ships **13** languages (de, en, es, fr, it, ja, ko, pl, pt, ru, tr, zh-Hans, zh-Hant)
across 7 `.xcstrings` catalogs; Tauri ships ~30. Mechanism (already built):
`script/localization_expand.py` — `seed` reuses Tauri translations by exact English
match (adds the language to every catalog), `gaps-unique` emits the remaining
**1481** unique English strings (each with a `zhHans` reference + Apple `%@`/`%lld`
placeholders), `apply-english` broadcasts a `{en:{lang:val}}` table into the catalogs
(fills gaps only, never overwrites). `verify_localization_catalog.py` enforces parity +
placeholder match + `state: translated`; new languages also need `CFBundleLocalizations`
in the `Config/*-Info.plist` files. RTL (ar, fa, he, ur) deferred ("No RTL yet" — needs
layout-mirroring audit).

Parallelization: background translator subagents produce translation-pack-shaped JSON
responses with nested `translations` and no repo writes → zero conflict; the controlling
session runs `seed --write` + `apply-pack` + `verify --write-bundle-localizations` + the
gate, then commits each batch. **Apply pipeline validated.** The seed script now resolves Tauri
locales through `LORVEX_TAURI_LOCALES`, the monorepo `apps/tauri/app/src/locales` path, or
the sibling `lorvex_original/app/src/locales` checkout, so the expansion path is not tied
to a single workspace layout. It also emits and applies `InfoPlist.strings` gaps per
shipping target, so permission text and quick-action titles are covered by the same
translation payload instead of a separate manual pass. `translation-pack` now combines
deduplicated `.xcstrings` gaps, occurrence metadata, translator instructions, and
InfoPlist gaps into a single per-language JSON input artifact. Preflight commands
`validate-english` and `validate-info-plist` reject empty translations, unknown target
languages/targets, and printf placeholder drift before any translated payload is written.
`apply-pack` validates both `catalogStrings` and `infoPlistStrings` before writing either
side, supports responses that preserve the original `langs`/`missing` metadata with nested
`translations`, and rejects metadata-backed rows whose required languages are incomplete.
The default script target set is now the remaining non-RTL expansion batch:
`hi, id, vi, uk, nl, th, ro, ms, bn, el, ta, te, mr, ml`.

Landed (13 languages total): **it, pl, tr** — full catalog + InfoPlist.strings + bundle
plists; gate + 1556 tests green. Turkish needed 14 dialog strings switched to positional
specifiers (`%1$d`/`%2$@`) so its postpositional word order keeps the English arg sequence.
In flight / queued target batch: `hi, id, vi, uk, nl, th, ro, ms, bn, el, ta, te, mr, ml`.

---

## Tauri (parity reference — lower priority)

No open Tauri parity items right now.
