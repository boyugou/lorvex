# RFC-004: Life Data Model Extension

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


**Status:** DRAFT — Only `list_type` and `target_date` columns from this RFC exist in schema; journal/goals/finance modules not started
**Author:** Claude (Opus 4.6)

---

## Context

The core insight from the "Comfortable Backend" and "Life Trajectory" analysis:
the database is not just a task list — it's a persistent record of the user's life
that AI reads and builds context from. This creates a compounding advantage over time.

The current schema supports tasks, lists, current focus, and preferences. This RFC
considers how to extend the data model to support broader life-management data
that users naturally want to store: goals, reading lists, journal entries, etc.

## Design Principles

1. **Don't over-model.** The current task schema is already flexible enough to
   handle many "non-task" items via status variants and tags.
2. **Prefer composition over new tables.** A "goal" is a list with a target date.
   A "reading list item" is a task with tag "reading" and status "someday."
3. **Only add new tables when the entity genuinely can't be modeled as a task.**
4. **Every new entity needs MCP tools.** No data type should exist without a way
   for Claude to CRUD it via MCP.

## Analysis: What Users Want to Store

| User intent | Current representation | Adequate? |
|---|---|---|
| "Remind me to buy groceries" | Task (status=open) | ✅ Yes |
| "I want to read Thinking Fast and Slow" | Task (status=someday, tag=reading) | ✅ Adequate |
| "My goal is to run a marathon by June" | List ("Marathon Training") + tasks | ⚠️ Works but lacks target date on the list |
| "Today was a good day, finished the proposal" | No entity exists | ❌ No |
| "I want to learn Rust this quarter" | Task (status=someday, tag=learning) | ⚠️ Loses the "quarter" time horizon |
| "Key insight: X causes Y" | No entity exists | ❌ No |

## Proposed Changes

### Phase 1 (MVP+1): Extend lists with `target_date` and `type`

```sql
ALTER TABLE lists ADD COLUMN type TEXT NOT NULL DEFAULT 'list';
-- Valid types: 'list', 'project', 'goal', 'area'
ALTER TABLE lists ADD COLUMN target_date TEXT;
-- For goals/projects with deadlines
ALTER TABLE lists ADD COLUMN status TEXT NOT NULL DEFAULT 'active';
-- Valid: 'active', 'completed', 'archived'
```

This lets Claude create:
- A **goal** with a deadline: `{ type: 'goal', name: 'B2 Spanish', target_date: '2026-12-31' }`
- A **project** with a target: `{ type: 'project', name: 'Marathon', target_date: '2026-06-15' }`
- An **area** of responsibility: `{ type: 'area', name: 'Health' }` (ongoing, no deadline)

The sub-items of each are still regular tasks. No new table needed.

### Phase 2 (Post-MVP): Journal entries

Journal entries are genuinely different from tasks — they have no status, no completion,
no urgency. They are temporal records of experience.

```sql
CREATE TABLE IF NOT EXISTS journal_entries (
  id          TEXT PRIMARY KEY,
  date        TEXT NOT NULL,     -- YYYY-MM-DD
  body        TEXT NOT NULL,     -- Markdown content
  mood        TEXT,              -- Optional: 'great', 'good', 'neutral', 'rough', 'bad'
  tags        TEXT,              -- JSON: string[]
  ai_summary  TEXT,              -- Claude's summary of the entry
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);
```

MCP tools: `add_journal_entry`, `get_journal_entry`, `get_journal_range`.

Claude can then reference journal entries in planning: "Yesterday you wrote you
felt drained. Keeping today's plan light: 2 focus items instead of 4."

### Phase 3 (Future): Knowledge/insights store

For capturing personal insights, learnings, and reference notes. This is the most
speculative and least urgent. Defer until real usage patterns emerge.

## Decision

- **Phase 1:** Accept for next iteration. The list type/target_date extension
  is minimal and high-leverage.
- **Phase 2:** Accept in principle, implement after core app is solid.
- **Phase 3:** Defer. Insufficient signal on whether users want this vs. using
  a separate notes app.

## Non-Goals

- We are NOT building a second brain or a freeform knowledge-graph app. The scope is
  structured life data that AI can reason over, not freeform knowledge graphs.
- We are NOT building social features. This is a single-user system.
