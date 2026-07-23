# Data export format

The data export is a **semantic, AI-reconciled best-effort document for
cross-tool migration** — a human- and model-meaningful snapshot of what the user
has, not a lossless or byte-parity sync interchange. It carries the product
entities (tasks, lists, tags, habits, calendar events, reviews, focus, memory,
preferences) with their meaningful fields and drops the replication scaffolding
the app uses internally. Moving data between Lorvex implementations reconciles
these semantics; it does not replay a change log or reproduce byte-identical
rows. See `README.md` for how this sits against the byte-canonical *sync*
contract, which is a separate thing.

The Apple app is the canonical producer of this format. The MCP `export_data`
tool emits it; the in-app data importer reads it back.

## Two container shapes

The same per-entity DTOs render into two containers:

- **Single-file JSON** — one JSON document with a top-level `formatVersion`, a
  provenance `manifest`, one array per included entity category, and the
  single-object `nativeTaskGraph` member when a restore-grade task export is
  included. This is what the `export_data` MCP tool returns for
  `format: "json"`, and what this document specifies in full.
- **ZIP package** — a `manifest.json` (a different, ZIP-only manifest shape:
  `schemaVersion`, optional `generatedAt`, optional `appVersion`, and
  `fileCounts` mapping each member's base name to its record count) plus one
  `<member>.json` file per included category. The member inventory is **closed**:
  the thirteen recognized members are `tasks.json`, `native_task_graph.json`,
  `lists.json`, `tags.json`, `habits.json`, `calendar_series_cutovers.json`,
  `calendar_events.json`, `daily_reviews.json`, `current_focus.json`,
  `focus_schedules.json`, `task_calendar_event_links.json`, `memory.json`, and
  `preferences.json`; an unrecognized entry rejects the import. Every member is
  an array of the same entity DTOs except `native_task_graph.json`, which holds
  one snapshot object.

A `format: "csv"` export renders the same entities as multi-section CSV and
carries **no** manifest; it is a convenience view, not a re-import target for the
single-file JSON path.

Producer: `LorvexDataExporter`
(`apps/apple/Sources/LorvexCore/Support/LorvexDataExporter.swift`). JSON is
pretty-printed with **sorted keys**, so identical input produces byte-stable
output; the key ordering in the example below is illustrative, not the emitted
order.

## Top-level structure (single-file JSON)

Container DTO: `LorvexDataExportPayload`
(`apps/apple/Sources/LorvexCore/Support/LorvexDataExport.swift`).

| Key | Type | Notes |
|-----|------|-------|
| `formatVersion` | string | Export envelope version. Current and first-public value **`"1"`**. The importer is fail-fast: a single-file JSON with no `formatVersion`, or a value without an explicit decoder in this build, is rejected rather than mis-decoded. Released decoders are retained when later versions are appended. |
| `manifest` | object | Required provenance + exact inventory header (see below). Stamped for JSON exports; absent from CSV. Provenance is never applied, while its versions and counts are verified before import. |
| entity members | array (object for `nativeTaskGraph`) | One key per included category. A category not included in the export run is **omitted entirely** (not emitted as `null` or `[]`). Public v1 rejects every unknown top-level key rather than treating a typo as an omitted category. |

The entity-array keys are **camelCase** and are distinct from the category raw
values used for CSV headers, ZIP file names, and `manifest.entityCounts` keys:

| camelCase key | category raw value | entity DTO |
|---------------|--------------------|------------|
| `tasks` | `tasks` | `ExportTask` |
| `nativeTaskGraph` | `native_task_graph` | `NativeTaskGraphSnapshot` (single object, not an array — see below) |
| `lists` | `lists` | `ExportList` |
| `tags` | `tags` | `ExportTag` |
| `habits` | `habits` | `ExportHabit` |
| `calendarSeriesCutovers` | `calendar_series_cutovers` | `ExportCalendarSeriesCutover` |
| `calendarEvents` | `calendar_events` | `ExportCalendarEvent` |
| `dailyReviews` | `daily_reviews` | `ExportDailyReview` |
| `currentFocus` | `current_focus` | `ExportCurrentFocus` |
| `focusSchedules` | `focus_schedules` | `ExportFocusSchedule` |
| `taskCalendarEventLinks` | `task_calendar_event_links` | `ExportTaskCalendarEventLink` |
| `memory` | `memory` | `ExportMemoryEntry` |
| `preferences` | `preferences` | `ExportPreference` |

`nativeTaskGraph` and `calendarSeriesCutovers` are internal restore
dependencies, not separately selectable export categories: they ride along with
the `tasks` and `calendarEvents` selections respectively so a restore can apply
them before the rows that depend on them.

### `manifest`

DTO: `ExportPayloadManifest` (same file). This is the single-file analogue of
the ZIP package's `manifest.json`.

| Key | Type | Notes |
|-----|------|-------|
| `formatVersion` | string | Mirrors the payload envelope (`"1"`). |
| `schemaVersion` | string | Data-model version stamp. Current and first-public value **`"1"`**. |
| `generatedAt` | string? | Wall-clock ISO-8601 of the export. Present when the caller supplies it (the MCP tool does); omitted otherwise. |
| `source` | object | Producing app/device — see below. |
| `entityCounts` | object | Exact map of **category raw value** → decoded record count, one entry per included selectable category. The importer rejects missing/extra declarations and count mismatches. `nativeTaskGraph` and `calendarSeriesCutovers` ride with their parent categories and are not counted separately. |

`source` is `ExportSource` (same file):

| Key | Type | Notes |
|-----|------|-------|
| `platform` | string | Always `"apple"` for this producer. |
| `appVersion` | string? | Marketing version of the producing app; omitted when the caller cannot supply it. |
| `deviceID` | string? | Producing device id, read from the store session. |

`source` is **provenance for an AI-driven migration**, not destination state,
and is never applied. The containing `manifest` is nevertheless a required
compatibility/inventory contract verified before preview or restore.

## Entity field reference

Every field below exists in the cited DTO. Optional (`?`) fields are **omitted**
from the JSON when they have no value. A handful of relationship/collection
fields are non-optional and are therefore **always present**, rendered as `[]`
when empty; those are called out per entity. Timestamps are ISO-8601 strings;
task `dueDate` / `plannedDate` / `availableFrom` carry the fractional-millisecond
`Z` precision the core stores.

### `tasks` — `ExportTask` (`Support/ExportTask.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | |
| `title` | string | |
| `notes` | string? | Task body. Omitted when empty. |
| `priority` | string | Priority raw value. |
| `status` | string | Status raw value: one of `open`, `in_progress`, `completed`, `cancelled`, `someday`. A full export includes every status and archived rows. |
| `dueDate` | string? | |
| `plannedDate` | string? | |
| `availableFrom` | string? | |
| `estimatedMinutes` | int? | |
| `tags` | [string]? | Tag display names as a first-class array. Omitted when the task has no tags. |
| `rawInput` | string? | |
| `dependsOn` | [string]? | Blocker task ids as a first-class array. Omitted when the task blocks on nothing. |
| `listID` | string? | |
| `aiNotes` | string? | |
| `checklist` | [object]? | Checklist rows in display order. Omitted when none. |
| `reminders` | [object]? | Reminder rows in reminder-time order. Omitted when none. |
| `recurrence` | object? | Structured recurrence rule — see [Recurrence](#recurrence). Omitted for a non-recurring task. |
| `recurrenceExceptions` | [string]? | Skipped-occurrence dates (`YYYY-MM-DD`). Omitted when none. |
| `deferCount` | int? | |
| `lastDeferReason` | string? | |
| `lastDeferredAt` | string? | |
| `completedAt` | string? | |
| `createdAt` | string? | |
| `updatedAt` | string? | |
| `archivedAt` | string? | |

`checklist` item (`ExportChecklistItem`): `id?`, `position?`, `text`,
`completed` (bool), `completedAt?`, `createdAt?`, `updatedAt?`.

`reminders` item (`ExportTaskReminder`): `id`, `reminderAt`, `dismissedAt?`,
`cancelledAt?`, `createdAt?`, `originalLocalTime?`, `originalTz?`.

### `lists` — `ExportList` (`Support/ExportList.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | |
| `name` | string | |
| `description` | string? | Omitted when empty. |
| `color` | string? | Sidebar accent `#RRGGBB`. |
| `icon` | string? | SF Symbol name. |
| `aiNotes` | string? | AI-authored list scope/profile notes. |
| `archivedAt` | string? | `nil`/absent means active. |
| `position` | int | Manual display order. |

Both active and archived lists are included.

### `tags` — `ExportTag` (`Support/ExportTag.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | |
| `displayName` | string | |
| `color` | string? | |
| `createdAt` | string? | |
| `updatedAt` | string? | |

### `habits` — `ExportHabit` (`Support/ExportHabit.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | |
| `name` | string | |
| `cue` | string | `""` when unset. |
| `frequencyType` | string | `daily` / `weekly` / `monthly` / `times_per_week`. |
| `weekdays` | [int] | **Always present.** Monday-first (`0`=Mon … `6`=Sun); `[]` when the cadence carries no weekday set. |
| `perPeriodTarget` | int? | `times_per_week` count. |
| `dayOfMonth` | int? | `monthly` day-of-month. |
| `targetCount` | int | Per-day accumulative goal, decoupled from the cadence. |
| `milestoneTarget` | int? | |
| `icon` | string? | |
| `color` | string? | |
| `archived` | bool | |
| `position` | int | |
| `completions` | [object] | **Always present** (`[]` when none). |
| `reminderPolicies` | [object] | **Always present** (`[]` when none). |

`completions` item (`ExportHabitCompletion`): `completedDate`, `value` (int),
`note?`, `createdAt`, `updatedAt`. `reminderPolicies` item
(`ExportHabitReminderPolicy`): `id`, `reminderTime`, `enabled` (bool),
`createdAt`, `updatedAt`. Both active and archived habits are included.

### `calendarEvents` — `ExportCalendarEvent` (`Support/ExportCalendarEvent.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | |
| `title` | string | |
| `startDate` | string | `YYYY-MM-DD`. |
| `startTime` | string | `""` for an all-day or time-less event. |
| `endDate` | string | `""` when unset. |
| `endTime` | string | `""` when unset. |
| `allDay` | bool | |
| `location` | string? | Omitted when empty. |
| `notes` | string? | |
| `url` | string? | |
| `color` | string? | |
| `eventType` | string | Defaults to `"event"`. |
| `personName` | string? | |
| `attendees` | [object]? | Omitted when none. A lightweight `{name?, email?}` annotation (at least one non-empty per entry); `email` may be `""` for a name-only entry. No RSVP/PARTSTAT status. |
| `timezone` | string? | |
| `recurrence` | object? | Structured recurrence rule — see [Recurrence](#recurrence). Omitted when none. |
| `seriesId` | string? | Originating master ID for an occurrence decision; omitted for a base event. |
| `recurrenceInstanceDate` | string? | Original `YYYY-MM-DD` occurrence addressed by a decision. |
| `occurrenceState` | string? | `replacement`, `cancelled`, or `inherit` for a decision; omitted for a base event. |
| `recurrenceGeneration` | string? | Recurring-master generation, or the generation a decision belongs to. |
| `seriesCutoverId` | string? | Durable tail-boundary identity for a base segment; omitted for roots and occurrence decisions. |

A full export spans the store's entire calendar history. Occurrence decisions
are exported as final-state rows; there is no separate calendar EXDATE array or
restore history.

### `dailyReviews` — `ExportDailyReview` (`Support/ExportDailyReview.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `date` | string | `YYYY-MM-DD`. |
| `summary` | string | |
| `mood` | int? | |
| `energyLevel` | int? | |
| `wins` | string | `""` when none. |
| `blockers` | string | `""` when none. |
| `learnings` | string | `""` when none. |
| `timezone` | string? | |
| `updatedAt` | string? | |
| `linkedTaskIDs` | [string] | **Always present** (`[]` when none). |
| `linkedListIDs` | [string] | **Always present** (`[]` when none). |

### `currentFocus` — `ExportCurrentFocus` (`Support/ExportFocus.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `date` | string | `YYYY-MM-DD`. |
| `briefing` | string? | |
| `timezone` | string? | |
| `taskIDs` | [string] | **Always present** (`[]` when none), in focus order. |
| `createdAt` | string? | |
| `updatedAt` | string? | |

### `focusSchedules` — `ExportFocusSchedule` (`Support/ExportFocus.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `date` | string | `YYYY-MM-DD`. |
| `rationale` | string? | |
| `timezone` | string? | |
| `blocks` | [object] | **Always present** (`[]` when none). |
| `createdAt` | string? | |
| `updatedAt` | string? | |

`blocks` item (`ExportFocusScheduleBlock`): `position` (int), `blockType`,
`startMinutes` (int), `endMinutes` (int), `taskID?`, `calendarEventID?`,
`eventSource?` (`canonical` / `provider` / `freeform`), `title?`.

### `taskCalendarEventLinks` — `ExportTaskCalendarEventLink` (`Support/ExportTaskCalendarEventLink.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `taskID` | string | |
| `calendarEventID` | string | |
| `createdAt` | string? | |
| `updatedAt` | string? | |

### `memory` — `ExportMemoryEntry` (`Support/ExportMemoryEntry.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string? | |
| `key` | string | |
| `content` | string | |
| `updatedAt` | string | |

### `preferences` — `ExportPreference` (`Support/ExportPreference.swift`)

| Field | Type | Notes |
|-------|------|-------|
| `key` | string | |
| `value` | string | The JSON-encoded stored payload string, as stored. |

Device-local preference keys (`PreferenceKeys.isLocalOnlyPreference`) are
**filtered out**: one device's private/config state (notification toggles, sync
backend choice, …) never rides an export to another device.

## Recurrence

Both recurring surfaces carry `recurrence` as a **structured object** with the
same camelCase field vocabulary. The object keys are camelCase, but the *values*
are the canonical RFC-5545-aligned tokens (uppercase `freq`, `MO`-style weekday
codes) defined in `RECURRENCE.md`. Read that document for what each field means
and how a rule normalizes; the tables below only fix how the rule is projected
into an export.

- **Tasks** carry `recurrence` as `ExportRecurrenceRule` (in
  `Support/ExportTask.swift`), mirroring the task's recurrence rule
  field-for-field:

  | Field | Type | Notes |
  |-------|------|-------|
  | `freq` | string | `DAILY` / `WEEKLY` / `MONTHLY` / `YEARLY`. |
  | `interval` | int? | |
  | `byDay` | [string]? | Weekday codes `MO`…`SU` (with an optional ordinal prefix for MONTHLY/YEARLY). |
  | `byMonth` | [int]? | |
  | `byMonthDay` | [int]? | |
  | `bySetPos` | [int]? | |
  | `wkst` | string? | |
  | `until` | string? | `YYYY-MM-DD`. |
  | `count` | int? | |
  | `anchor` | string? | `completion` when completion-anchored; **omitted** for the default `schedule`. |

- **Calendar events** carry `recurrence` as `ExportCalendarRecurrenceRule` (in
  `Support/ExportCalendarEvent.swift`), the same shape **minus `anchor`**: the
  completion anchor is a task-only concept (the calendar recurrence normalizer
  rejects `ANCHOR` — events have no completion), so a calendar rule can never
  carry it.

  | Field | Type | Notes |
  |-------|------|-------|
  | `freq` | string | `DAILY` / `WEEKLY` / `MONTHLY` / `YEARLY`. |
  | `interval` | int? | Canonical storage always applies the `1` default, so it is normally present. |
  | `byDay` | [string]? | Weekday codes `MO`…`SU` (with an optional ordinal prefix for MONTHLY/YEARLY). |
  | `byMonth` | [int]? | |
  | `byMonthDay` | [int]? | |
  | `bySetPos` | [int]? | |
  | `wkst` | string? | |
  | `until` | string? | `YYYY-MM-DD`. |
  | `count` | int? | Capped at 365 for calendar events. |

  The exporter parses the canonical JSON stored in `calendar_events.recurrence`
  into this object; the importer renders it back to that canonical string, which
  the calendar recurrence normalizer re-validates, so an exported rule
  round-trips to the same stored recurrence.

Tasks carry skipped occurrences separately as first-class
`recurrenceExceptions` date arrays (`YYYY-MM-DD`). Calendar recurrence uses a
different final-state contract: base events carry the rule, per-occurrence rows
carry `seriesId`, `recurrenceInstanceDate`, `occurrenceState`, and
`recurrenceGeneration`, and durable tail boundaries are exported through
`calendarSeriesCutovers`. Calendar events do not carry an EXDATE array.

## Internal restore-dependency members

### `calendarSeriesCutovers`

DTO: `ExportCalendarSeriesCutover`
(`apps/apple/Sources/LorvexCore/Support/ExportCalendarSeriesCutover.swift`).
One row per durable recurring-calendar lineage boundary. Sync clocks are
deliberately omitted: restore mints fresh local provenance, while the
deterministic identity, boundary date, and absorbing state are the data
contract.

| Key | Type | Notes |
|-----|------|-------|
| `id` | string | Deterministic cutover identity. |
| `lineageRootId` | string | Root event id of the recurring lineage this boundary belongs to. |
| `cutoverDate` | string | `YYYY-MM-DD` boundary date. |
| `state` | string | Absorbing lifecycle state of the boundary. |

### `nativeTaskGraph`

DTO: `NativeTaskGraphSnapshot`
(`apps/apple/Sources/LorvexCore/Support/NativeTaskGraphSnapshot.swift`). The
exact-restore internal representation of the task aggregate graph — one
snapshot object, not an array — included when the `tasks` category exports in
a restore-grade container (JSON/ZIP backups; AI-oriented and CSV exports omit
it).
It is versioned independently of the envelope through its own `schemaVersion`
member (currently `"1"`; the importer accepts exactly the version pinned by
`BackupV1Contract.nativeTaskGraphSchemaVersion` and rejects others). Top-level
members: `schemaVersion`, `tasks`, `recurrenceExceptions`, `tagEdges`,
`dependencyEdges`, `checklistItems`, `reminders`, `tombstones`, and
`payloadShadows`. Unlike the portable entity arrays, this member carries
replication metadata (HLC versions, tombstones, payload shadows) because its
job is bit-faithful task-graph reconstruction on restore, not AI-reconciled
migration.

## What is deliberately omitted

The export is a semantic snapshot, so it drops everything that only makes sense
inside one running store:

- **Sync/replication internals.** Per-row HLC version vectors and other
  replication bookkeeping the sync layer maintains are not exported. The export
  carries the entity's meaningful fields, not its change-log position.
- **Recurrence-materialization bookkeeping.** The internal columns used to expand
  a recurring series in-app (`recurrence_group_id`, `recurrence_instance_key`,
  and the canonical-occurrence anchor) are not exported; the export carries the
  human-meaningful rule plus its skip dates instead.
- **Device-local preferences.** Local-only preference keys are filtered out (see
  `preferences` above).
- **Derived / view-scoped noise.** The export reads full tables (every status,
  full calendar history) rather than a UI view, and emits the stored fields —
  not counters or projections recomputed for a particular screen.

Because these are dropped by design, an export is **not** a replication log and
**not** a byte-for-byte restore image. Re-importing reconstructs the semantics;
it does not reproduce the original rows bit-for-bit.

## Import / round-trip contract

The in-app importer (`LorvexDataImporter`) accepts either a single-file JSON
export or a ZIP package (`LorvexDataImporter+Decode.swift`):

- **Single-file JSON** must carry a `formatVersion` with an explicit decoder in
  the build. Version `"1"` is the first public contract and remains supported
  when a future exporter advances to v6. A missing or unrecognized version is
  rejected rather than being decoded through the current DTO. Public v1 also
  requires its inline `manifest`, rejects unknown top-level members, and
  requires `entityCounts` to match the included selectable categories exactly;
  partial-category backups remain valid when the manifest names exactly that
  partial set.
- **ZIP package** must contain a `manifest.json` whose `schemaVersion` the build
  supports, and whose per-file record counts **exactly match** the archive
  inventory; a missing manifest, incompatible version, or count mismatch is
  rejected. Version `"1"` is likewise the first public ZIP contract and has its
  own retained decoder branch.

Committed v1 fixtures under
`apps/apple/Tests/Fixtures/BackupFormat/` are compatibility artifacts, not
examples to regenerate when the current exporter advances. Tests decode those
unchanged bytes/members through the retained v1 branches.

Hand-written or AI-authored JSON is not imported directly; recreate that data
through the MCP tools instead.

## Relationship to `spec/`

This document specifies the **semantic migration** document. It is separate from
the byte-canonical **sync** contract (`RECURRENCE.md`, the `canonical-json`
fixtures), which pins the exact bytes Apple's sync checksums depend on. The two
must not be conflated: the export is best-effort and reconciled; the sync
canonical form is byte-locked for Apple's own producer. See `README.md`.

The `spec/fixtures/tauri-export-golden.zip` fixture is **not** an example of
this format. It is a Tauri-produced, deflate-compressed archive in a
sync-sharded JSONL layout (`entities.jsonl`, `edges.jsonl`, `tombstones.jsonl`,
…), committed as a golden for the Swift ZIP reader's inflate path
(`LorvexZipArchiveTests.readsDeflateCompressedTauriExportFixture`). Do not read
it as a sample of the Apple export.

## Example (single-file JSON)

An `all`-category export with one recurring task, one list, one tag, one habit,
one recurring calendar event, one memory entry, and one preference. Key ordering
is illustrative; the encoder emits sorted keys.

```json
{
  "formatVersion": "1",
  "manifest": {
    "formatVersion": "1",
    "schemaVersion": "1",
    "generatedAt": "2026-07-12T14:03:11.482Z",
    "source": {
      "platform": "apple",
      "appVersion": "1.4.0",
      "deviceID": "8F2A1C90-3B7E-4D22-9E01-6C4F0A1B2D33"
    },
    "entityCounts": {
      "tasks": 1,
      "lists": 1,
      "tags": 1,
      "habits": 1,
      "calendar_events": 1,
      "memory": 1,
      "preferences": 1
    }
  },
  "tasks": [
    {
      "id": "task-1",
      "title": "Weekly review",
      "notes": "Clear the inbox and plan next week.",
      "priority": "P1",
      "status": "open",
      "dueDate": "2026-07-13T17:00:00.000Z",
      "estimatedMinutes": 30,
      "tags": ["planning"],
      "dependsOn": ["task-0"],
      "listID": "list-1",
      "recurrence": {
        "freq": "WEEKLY",
        "interval": 1,
        "byDay": ["MO"]
      },
      "recurrenceExceptions": ["2026-07-27"],
      "createdAt": "2026-01-04T09:00:00.000Z",
      "updatedAt": "2026-07-06T18:20:00.000Z"
    }
  ],
  "lists": [
    {
      "id": "list-1",
      "name": "Work",
      "description": "Work tasks",
      "color": "#FF5733",
      "icon": "briefcase",
      "position": 1
    }
  ],
  "tags": [
    { "id": "tag-1", "displayName": "planning", "color": "#3366FF" }
  ],
  "habits": [
    {
      "id": "habit-1",
      "name": "Morning walk",
      "cue": "after coffee",
      "frequencyType": "daily",
      "weekdays": [],
      "targetCount": 1,
      "archived": false,
      "position": 0,
      "completions": [
        {
          "completedDate": "2026-07-11",
          "value": 1,
          "createdAt": "2026-07-11T07:30:00.000Z",
          "updatedAt": "2026-07-11T07:30:00.000Z"
        }
      ],
      "reminderPolicies": []
    }
  ],
  "calendarEvents": [
    {
      "id": "event-1",
      "title": "Team standup",
      "startDate": "2026-07-13",
      "startTime": "09:30",
      "endDate": "2026-07-13",
      "endTime": "09:45",
      "allDay": false,
      "eventType": "event",
      "timezone": "America/New_York",
      "recurrence": {
        "freq": "WEEKLY",
        "interval": 1,
        "byDay": ["MO", "WE", "FR"]
      }
    }
  ],
  "memory": [
    {
      "id": "mem-1",
      "key": "user_timezone",
      "content": "America/New_York",
      "updatedAt": "2026-05-02T12:00:00.000Z"
    }
  ],
  "preferences": [
    { "key": "week_start_day", "value": "\"monday\"" }
  ]
}
```
