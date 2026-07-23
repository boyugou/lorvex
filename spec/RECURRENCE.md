# Recurrence rule contract

The recurrence rule is a canonical JSON object (Apple stores it in
`tasks.recurrence`, and — without the `ANCHOR` extension below — in
`calendar_events.recurrence`). What follows is the SEMANTIC contract: what each
key means and how a rule normalizes.

Apple emits the JSON byte-canonically (keys sorted, defaults applied) because
Apple's own sync checksums depend on stable bytes. A companion implementation
converges to these *semantics* rather than byte-locking to Apple's schema —
cross-platform data transfer is AI-reconciled best-effort, not a byte-equality
contract.

## Canonical shape

A JSON object whose keys are a subset of the RFC 5545-aligned set plus the Lorvex
`ANCHOR` extension. Keys are emitted in UTF-8 byte-sorted order (matching
serde_json's `BTreeMap` serialization), defaults are applied, and unknown keys are
rejected at normalization time.

| Key          | Type            | Notes |
|--------------|-----------------|-------|
| `FREQ`       | string          | Required. `DAILY` / `WEEKLY` / `MONTHLY` / `YEARLY`. |
| `INTERVAL`   | integer ≥ 1     | Defaults to 1. |
| `BYDAY`      | array of codes  | `MO`…`SU`, optional ordinal prefix for MONTHLY/YEARLY. WEEKLY/MONTHLY/YEARLY only. |
| `BYMONTH`    | array 1..12     | WEEKLY/MONTHLY/YEARLY only. |
| `BYMONTHDAY` | array ±1..31    | MONTHLY/YEARLY only. Sorted + deduped (`[1,15]` = 1st and 15th). A bare integer is accepted on input for back-compat and normalizes to a one-element array. |
| `BYSETPOS`   | array ±1..366   | MONTHLY/YEARLY only. |
| `WKST`       | weekday code    | |
| `UNTIL`      | YYYY-MM-DD      | Mutually exclusive with `COUNT`. |
| `COUNT`      | integer ≥ 1     | Mutually exclusive with `UNTIL`. Calendar events cap at 365. |
| `ANCHOR`     | string          | Lorvex extension — see below. |

## The `ANCHOR` extension (completion-anchored recurrence)

`ANCHOR` selects what the next occurrence is measured from:

- **`schedule`** (default): the fixed calendar cadence, anchored on the task's
  `canonical_occurrence_date`. Every Monday, the 1st of each month, etc.
- **`completion`**: the next occurrence lands `INTERVAL` `FREQ`-units after the
  task is *completed*, so a task finished late slips forward instead of piling up
  missed occurrences.

Rules:

1. `schedule` is **omitted** from canonical output. A rule with `ANCHOR=schedule`
   normalizes byte-identically to one with no `ANCHOR` key, so every pre-existing
   fixed-cadence rule is unchanged — no migration, no schema column.
2. `ANCHOR=completion` is **incompatible with positional keys**
   (`BYDAY`/`BYMONTH`/`BYMONTHDAY`/`BYSETPOS`/`WKST`): the next date is computed
   purely from the completion day, so a fixed weekday/month is meaningless and is
   rejected rather than silently ignored.
3. `ANCHOR` is **task-only**. The calendar-event normalizer rejects it — events
   have no completion.
4. Advancement: on completion, the successor's `due_date` and
   `canonical_occurrence_date` are set to `completion_day + INTERVAL` units of
   `FREQ` (months/years clamp the day-of-month against shorter months). `UNTIL`
   and `COUNT` apply as usual; `EXDATE` skips carry over.

## Companion-implementation alignment (not a byte-lock)

`ANCHOR` is an Apple concept; the Swift core (`apps/apple`) is its canonical
implementation. A companion implementation that wants completion-anchored
recurrence maps these *semantics* — add `ANCHOR` to its known-key set with the
`schedule`→omitted / `completion` normalization, and branch its successor's
next-due computation on the completion anchor. There is no parity *obligation*
and nothing enforces cross-runtime schema equality: the apps are directionally
aligned through this behavior contract, not byte-locked, and cross-platform data
movement is AI-reconciled best-effort.

An `ANCHOR=completion` rule read by an implementation that does not model the
extension degrades gracefully — the unknown key is ignored on read, so the rule
displays as fixed cadence; only re-normalizing it there would drop the unknown
key. No schema change is involved either way.

## In data exports

`EXPORT_FORMAT.md` projects this same rule two ways, and the vocabulary here is
authoritative for both:

- A **task** export carries a structured `recurrence` object whose keys are
  camelCase (`freq`, `interval`, `byDay`, `byMonthDay`, `bySetPos`, `wkst`,
  `until`, `count`, `anchor`) but whose *values* are the canonical tokens above —
  uppercase `FREQ` values (`WEEKLY`, …), `MO`…`SU` weekday codes, and the
  `schedule`/`completion` anchor (`schedule` omitted).
- A **calendar-event** export carries `recurrence` as a structured object with
  the same camelCase vocabulary **minus `anchor`** (`ANCHOR` is task-only —
  events have no completion, so the calendar normalizer rejects it). The exporter
  parses the canonical JSON stored in `calendar_events.recurrence` into the
  object; the importer renders it back to that canonical string, which the
  normalizer re-validates, so the rule round-trips to the same stored form.
