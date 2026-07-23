# Calendar Series Cutover Finalization

Status: implementation contract for the prelaunch schema baseline.

## Problem

`this_and_following` previously truncated the current recurring event and created an
independent tail with a random id. A concurrent topology edit from another device could
later restore the predecessor's untruncated recurrence while the tail remained live,
producing duplicate future occurrences. The truncated recurrence and the tail row were
two independently merged sources of truth with no durable relationship.

## Canonical Model

The durable cutover set is the only authority for partitioning a recurring lineage.
The predecessor's stored recurrence rule is never rewritten merely to represent a split.

`calendar_series_cutovers` is a synced, upsert-only relation:

- `id`: deterministic UUIDv8 derived from `(lineage_root_id, cutover_date)`.
- `lineage_root_id`: the original root event id. This is a soft reference so CloudKit
  arrival order and root deletion do not violate a foreign key. UUIDv8 is reserved for
  deterministic derived identities and is rejected here, so a cutover/occurrence id
  can never become the root of an overlapping nested lineage.
- `cutover_date`: the original recurrence slot (`YYYY-MM-DD`), never a moved display date.
- `state`: `active` or `deleted`.
- `version`, `created_at`, and `updated_at`.
- `(lineage_root_id, cutover_date)` is unique and immutable.

The root is implicit and has no cutover row. A tail is an ordinary base
`calendar_events` row whose `id` and immutable `series_cutover_id` both equal the
cutover id. Plain/root events and occurrence-decision rows have a null
`series_cutover_id`.

Cutover state is a remove-wins monotonic register:

- `active + active = active`, with the maximum valid HLC retained as the row high-water.
- `active + deleted = deleted`, regardless of arrival order.
- `deleted + deleted = deleted`, with the maximum valid HLC retained.
- `deleted` is absorbing. The same cutover id can never be reactivated.
- a sync `Delete` for a cutover is invalid; cutover rows never enter ordinary tombstone
  GC.

If a user later wants a new schedule beginning on the same date after deletion, the app
creates a new independent series. This avoids activation epochs and prevents old content,
topology registers, or occurrence decisions from becoming live again.

## Effective Projection

For each lineage, sort every durable cutover, including deleted cutovers, by
`cutover_date`:

- the implicit root owns slots before the first cutover;
- an active cutover at `D` owns `[D, next_cutover)` when its segment event exists;
- a deleted cutover at `D` creates a gap `[D, next_cutover)`;
- the final active segment owns `[D, infinity)` subject to its own recurrence rule;
- every predecessor is clipped dynamically; no split writes an `UNTIL` into its stored
  recurrence as a second source of truth.
- external calendar projections preserve the recurrence's RFC end shape: a bounded
  `COUNT` is reduced to the actual number of slots before the next cutover, an existing
  `UNTIL` is tightened, and only an unbounded rule gains `UNTIL = cutover - 1`.
  `COUNT` and `UNTIL` are never emitted together.

Occurrence membership is determined by the original recurrence slot. A replacement can
move its displayed date across a cutover without changing which segment owns the
decision.

Arrival order fails closed:

- segment event before cutover: do not materialize or display it; retain its envelope for
  retry;
- active cutover before segment event: predecessor is clipped and the interval is a
  temporary gap;
- deleted cutover before/after segment event: the segment event is not materialized and
  any stored copy is removed with its owned links/decisions;
- missing root does not hide later active segments.

## Product Semantics

- Splitting at a segment's first occurrence is an all-in-current-segment edit and does
  not create a zero-width cutover.
- `all_in_series` means the currently addressed segment, not every historical/future
  segment in the lineage.
- deleting a root/current segment leaves later segments intact.
- `delete this_and_following` at `D` creates a gap from `D` to the next existing or
  concurrent cutover. Therefore a later active cutover `E > D` resumes the lineage at
  `E`; the deletion is not a lineage-wide range tombstone.
- editing/deleting a single occurrence remains a deterministic decision on the owning
  segment and generation.

## Required Convergence Matrix

1. Root topology edit and split arrive in both orders: the predecessor is clipped and no
   future slot appears twice.
2. Two splits at the same date reuse one deterministic cutover/event identity.
3. Splits at `D1 < D2 < D3`, in every creation and arrival order, partition the lineage
   into ordered, non-overlapping intervals.
4. Active and deleted contenders for the same cutover converge to deleted, including an
   equal-HLC collision.
5. Delete at `D` plus split at `E > D` yields a gap `[D, E)` and an active tail from `E`.
6. Root deletion leaves later active tails visible.
7. Deleting a middle segment keeps later segments visible and leaves exactly one gap.
8. Late old segment envelopes cannot resurrect an absorbing deleted cutover.
9. Event-first, boundary-first, and authoritative-snapshot replay all fail closed without
   duplicates or private-content retention.
10. Decisions are assigned by `recurrence_instance_date`; moving replacement display
    dates across boundaries does not reassign them.
11. Native export/import preserves active and deleted cutovers before restoring segment
    events and decisions.
12. EventKit write-back uses its future-events span but never persists provider-derived
    truncation as Lorvex recurrence truth.

## Release Gate

This change is complete only when the root schema and embedded schema match, the numbered
sync payload contract includes the new entity and calendar marker, full-resync and
authoritative-snapshot paths preserve the relation, native export/import round-trips it,
the convergence matrix is covered by tests, and the complete Apple verification gate is
green.

The completed checkpoint additionally pins the integration surfaces that are easy to
miss when a sync entity is added:

- the cutover HLC participates in both local writer bootstrap and authoritative retry
  floors;
- current-schema base-calendar contenders still route to the grouped
  content/topology-register join instead of outer-row LWW;
- inbound dirty-domain reports attribute calendar records correctly and reload the
  calendar surfaces on macOS and mobile;
- System Intents, Spotlight, focus blocks, MCP projections, and provider links address
  a recurring segment by stable persistent event identity rather than an expanded
  occurrence id;
- EventKit all-day spans use explicit Gregorian civil-date projection and convert its
  exclusive end to Lorvex's inclusive end without shared formatter state;
- the superseded second ICS generator and the tests that preserved its incorrect
  all-day `DTEND` behavior are removed; the domain exporter is the sole implementation.

## Verification Evidence

- Root/embedded schema and checksum files are byte-identical. The migration ladder is
  still the correct empty prelaunch ladder (one baseline checksum, zero migrations).
- Root/embedded sync payload contracts are byte-identical, contiguous at version 1,
  and no `002` contract exists.
- CloudKit readiness passes with 20 syncable kinds; its Python verifier suite passes 37
  tests.
- Core `swift test`: 2,545 XCTest cases plus the Swift Testing provider-identity probe,
  zero failures (benchmark-only skips are explicit).
- App `swift build && swift test`: 449 XCTest cases plus 2,447 Swift Testing cases,
  zero failures.
- `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` passes, including production
  builds for the app, widget bundle, and MCP host; schema, privacy, localization,
  entitlement-shape, Mach-O closure, resource, hygiene, and local package verifiers are
  green.
- Independent MCP stdio smoke passes with 118 tools and real create/read operations.

The remaining signing/notarization and live App Group evidence requires a real
distribution identity and installed archive; it is release-operations evidence, not an
unresolved data-model or sync-contract defect.
