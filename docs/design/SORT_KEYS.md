# Sort Keys

This document catalogs the canonical task sort key and the allowed per-view deviations.

## Canonical Sort Key

```
priority_effective ASC, due_date ASC NULLS LAST, id ASC
```

This is the default sort order for task lists. `priority_effective` is computed by the core (lower number = higher priority). `id` is a stable UUIDv7 tiebreaker that preserves insertion order within the same priority/date bucket.

The canonical key is the default SQL ordering for general task lists. Views with a stronger user expectation, such as date-first timelines, recently-completed lists, or relevance-ranked search, may lead with another key and use the canonical key as the secondary tiebreaker. Any UI code that re-sorts a task list must either preserve this key or document a view-specific reason for deviation here.

## Adding a New Deviation

A new sort deviation is allowed when:
1. The view has a clear user expectation that the canonical key would violate (e.g. a "scheduled by time" view, a "recently completed" view).
2. The deviation is documented here with a rationale.
3. The deviation is applied only within its specific view — the canonical sort is not disturbed globally.

## Catalog of Allowed Deviations

> **Note:** Implementation-specific file references below are for the Apple app. The Tauri
> app's equivalent surfaces follow the same deviation rationale; file paths differ.

### Scheduled-tasks timeline view

**Sort:** `dueDate ASC, title ASC NULLS LAST`

**Rationale:** The scheduled-tasks view is a date-first timeline surface, not a priority briefing. Users who open this view expect to see tasks ordered chronologically by their scheduled date. Priority is a secondary concern in this specific view context.

**Apple file:** `Sources/LorvexApple/Stores/AppStoreTaskDerivedState.swift`

### Upcoming task buckets

**Sort:** `COALESCE(planned_date, due_date) ASC, priority_effective ASC, created_at DESC, id ASC`

**Rationale:** Upcoming is a date-first planning timeline. The canonical priority key is still the secondary key within a day.

**Apple file:** `apps/apple/core/Sources/LorvexStore/TaskRepoReadBuckets.swift`

### Scheduled (defer-until) section

**Sort:** `available_from ASC, priority_effective ASC, due_date ASC NULLS LAST, id ASC`

**Rationale:** The Scheduled section lists open tasks currently hidden by a
future `available_from` (defer-until) that are not yet overdue. It is a
date-first "when does this reappear" timeline, so the hide-until date leads;
the canonical task key is the secondary tiebreaker within a day.

**Apple file:** `apps/apple/core/Sources/LorvexStore/TaskRepoReadBuckets.swift`
(`getScheduledTasks`)

### High-priority undated bucket

**Sort:** `priority_effective ASC, created_at DESC, id ASC`

**Rationale:** This bucket exists specifically for important tasks that have no date. `due_date` is intentionally absent, so recency is the useful secondary signal.

**Apple file:** `apps/apple/core/Sources/LorvexStore/TaskRepoReadBuckets.swift`

### Deferred tasks

**Sort:** `defer_count DESC, id ASC`

**Rationale:** The deferred view is a triage surface for repeatedly postponed work, so deferral frequency leads.

**Apple file:** `apps/apple/core/Sources/LorvexStore/TaskRepoReadBuckets.swift`

### Recently completed tasks

**Sort:** `completed_at DESC, id ASC`

**Rationale:** Recent-completion views answer "what just got done", so completion time leads.

**Apple files:** `apps/apple/core/Sources/LorvexStore/TaskRepoRead.swift`, `apps/apple/core/Sources/LorvexWorkflow/WeeklyReview.swift`

### Weekly Review overdue panel

**Sort:** `due_date ASC, priority_effective ASC, id ASC`

**Rationale:** The Weekly Review overdue panel is a date-first overdue triage
surface — the most overdue tasks surface first — keeping the canonical key
(`priority_effective ASC, id ASC`) as the secondary tiebreaker.

**Apple file:** `apps/apple/core/Sources/LorvexWorkflow/WeeklyReview.swift` (`overdueItemsSQL`)

### Weekly Review someday panel

**Sort:** `created_at DESC, id ASC`

**Rationale:** The Weekly Review someday panel is recency-first triage for
undated Someday/Maybe tasks — the most recently added surface first; `id ASC`
makes the ordering deterministic.

**Apple file:** `apps/apple/core/Sources/LorvexWorkflow/WeeklyReview.swift` (`somedayItemsSQL`)

### Day-review top completed panel

**Sort:** `priority_effective ASC, due_date ASC NULLS LAST, id ASC`

**Rationale:** The day-review evidence panel is a "top completed" summary for
review writing, not a recency feed. It intentionally uses the canonical priority
key so the highest-priority completed work leads.

**Apple file:** `apps/apple/core/Sources/LorvexWorkflow/DayReview.swift`

### Task search

Search is relevance-ranked, and the ranking key differs by search strategy. Both strategies fall back to the canonical task key (`priority_effective ASC, due_date ASC NULLS LAST, id ASC`) as the stable tiebreaker inside equal relevance.

**FTS5 (BM25, Latin script):** `status_bucket ASC (open → someday → other), bm25(...) ASC, priority_effective ASC, due_date ASC NULLS LAST, id ASC`

**Trigram (CJK) / LIKE fallback:** `match_score DESC, priority_effective ASC, due_date ASC NULLS LAST, id ASC`

**Rationale:** Search must rank direct/relevant matches first, then fall back to the canonical task key for stable ordering inside equal scores. The FTS5 path additionally leads with an open-first status bucket so actionable matches surface above someday/done/archived ones, then ranks by BM25 relevance; SQLite's `bm25` returns smaller (more negative) values for stronger matches, so ascending order puts the best match first. The trigram/LIKE paths compute an integer `match_score` (title/body/tag/ai_notes hits) and order it descending; they carry no status bucket because their per-field scoring already privileges title matches. Using `updated_at` as any tiebreaker is disallowed: the HLC rewrites it on conflict resolution, so it can skip or duplicate rows across page boundaries after a sync.

**Apple file:** `apps/apple/core/Sources/LorvexStore/TaskRepoSearch.swift`

### Review history date-descending

**Sort:** `date DESC`

**Rationale:** Daily and weekly review history surfaces show most recent entries first.

**Apple files:** `Sources/LorvexMCPHost/ReviewHistoryToolHandlers.swift`, `Sources/LorvexCore/Services/SwiftLorvexCoreService+Review.swift`

### Checklist items by position

**Sort:** `position ASC`

**Rationale:** Checklist items have an explicit user-controlled position. This is not a task sort.

### Memory entries by updatedAt descending

**Sort:** `updatedAt DESC`

**Rationale:** Memory entries show most recently updated first, as stale entries are less relevant.

### Tags alphabetically

**Sort:** `lookup_key ASC` (localized case-insensitive)

**Rationale:** Tag lists are alphabetically sorted for human scanability. This is not a task sort.

## Non-Task Sorts (Not Subject to This Policy)

The following sorts are explicitly outside the scope of the canonical task sort key:

- CloudKit record name tie-breaking (`recordName ASC`) — internal sync ordering
- JSON key sorting (`sortedKeys`) — canonicalization for checksums and export
- Calendar event timeline sorting (`startDate ASC`) — temporal display
- Dependency graph sorting by planned date — internal dependency resolution
