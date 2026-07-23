# Review, Reflection, and Task MCP Design

This note records the product and implementation decision for Lorvex review/reflection data, weekly context tools, and task MCP query design.

## Scope

This document is about data schema and MCP contracts, not the visible UI labels. The current UI shape is acceptable:

- Daily reflection: the user writes a subjective daily entry.
- Weekly review: the user inspects a derived weekly activity view.

The implementation should keep those concepts clean in data and MCP surfaces.

## Current Code Findings

The current schema persists daily reflections only. The `daily_reviews` table stores the user's daily written content, mood, energy, wins, blockers, learnings, AI synthesis, timezone, and timestamps. There is no `weekly_reviews` table.

The weekly surface is derived. `WeekReviewDigest` is a read-only digest of daily review entries in the viewed week, and `WeeklyReview` builds aggregate activity snapshots/briefs from tasks and related data.

The MCP task query surface now exposes the richer store-backed filters that agents need for review workflows: status, list, priority, text, tags, due/planned/scheduled/completed/created/updated ranges, date presence, blocking filters, sort controls, pagination, and compact/full/field-shaped output.

The public `LorvexTask` model and MCP task values now expose task lifecycle audit fields:

- `created_at`
- `updated_at`
- `completed_at`

Agents can answer questions such as "what did I complete in the last 7 days?" through general task tools instead of relying on a fixed pattern-analysis tool.

## Product Terms

Use `reflection` for user-authored subjective entries.

Use `review` for inspecting recent activity and deciding what to do next.

Do not create a persisted weekly reflection model unless the product explicitly adds a weekly writing surface. A weekly review can remain a derived activity view.

## Data Model Decision

Keep `daily_reviews` as the only persisted reflection entity.

Do not add `weekly_reviews`.

Do not persist weekly-review-derived state unless a future feature needs explicit user-authored weekly writing. Weekly review data should be derived from tasks, daily reviews, habits, calendar, and other activity sources.

## MCP Surface Decision

Keep daily reflection tools:

- `get_daily_review`
- `add_daily_review`
- `amend_daily_review`
- `get_review_history`

Remove `get_weekly_review_snapshot` from MCP. The internal `WeeklyReviewSnapshot` read model can remain if the app UI uses it, but agents do not need a second compact weekly review tool when a richer brief or flexible task query is available.

Remove `analyze_task_patterns`. Pattern analysis should be performed by the agent over sufficiently rich task history, not by a fixed rule-based tool with overlapping semantics. The current implementation is also misleading because its `days` argument does not drive all of the underlying weekly-derived data.

Keep a single weekly brief only as convenience/context compression, not as a primary data primitive. Rename the current weekly MCP brief away from "weekly review snapshot" semantics. Preferred name:

- `get_weekly_brief`

Acceptable alternative if clarity is needed:

- `get_weekly_activity_brief`

This tool should be documented as syntactic sugar for common weekly context. Agents must be able to reproduce equivalent analysis through general read tools.

## Task Query Design

`list_tasks` should become the main task context primitive for agents.

Expose the store's existing range and sort capabilities through MCP:

- `status`: `open`, `completed`, `cancelled`, `someday`, `all`
- `list_id`
- `priority`
- `text`
- `tags`
- `due_from`, `due_to`
- `planned_from`, `planned_to`
- `scheduled_from`, `scheduled_to`
- `completed_from`, `completed_to`
- `created_from`, `created_to`
- `updated_from`, `updated_to`
- `due_presence`: `any`, `present`, `absent`
- `planned_presence`: `any`, `present`, `absent`
- `blocked_only`
- `blocking_others`
- `sort_by`
- `sort_direction`
- `limit`
- `offset`

`scheduled_*` should map to the existing `COALESCE(planned_date, due_date)` store query.

`updated_*` is not currently exposed by `TaskRepo.ListTasksQuery`; add it alongside the existing `createdRange` and `completedRange`.

Recommended `sort_by` values:

- `priority_due`
- `due_date`
- `planned_date`
- `scheduled_date`
- `created_at`
- `updated_at`
- `completed_at`
- `title`

The current store already supports several of these. Add missing axes only where the database can support deterministic pagination with `id ASC` as a tie breaker.

## Task Result Shape

Every task returned by MCP should include lifecycle audit fields:

- `created_at`
- `updated_at`
- `completed_at`

Keep existing task detail fields:

- `id`
- `title`
- `notes`
- `ai_notes`
- `priority`
- `status`
- `list_id`
- `estimated_minutes`
- `due_date`
- `planned_date`
- `recurrence`
- `recurrence_exceptions`
- `tags`
- `depends_on`
- `checklist_items`
- `reminders`
- `lateness_state`
- `defer_count`
- `last_defer_reason`
- `last_deferred_at`

Do not add a `fields` selector initially unless payload size becomes a real problem. The immediate design goal is correctness and agent convenience.

## Relationship Between `list_tasks` and `get_weekly_brief`

`list_tasks` should be the source of truth and the flexible primitive.

`get_weekly_brief` is optional convenience. Its purpose is to reduce repeated calls and token usage for common weekly review sessions. It must not contain unique rule logic that agents cannot reproduce with task queries.

If future usage shows that agents handle weekly context well through `list_tasks`, `get_weekly_brief` can be removed.

## Implementation Checklist

Completed:

1. Extended `LorvexTask` with `createdAt`, `updatedAt`, and `completedAt`.
2. Updated task row-to-model mapping to populate those fields.
3. Updated in-memory task service/test fixtures to carry those fields.
4. Updated MCP task value adapter to return `created_at`, `updated_at`, and `completed_at`.
5. Extended core task list service API to accept the richer query shape.
6. Exposed existing `TaskRepo.ListTasksQuery` filters through MCP `list_tasks`.
7. Added `updatedRange` to `TaskRepo.ListTasksQuery` and SQL where-clause composition.
8. Added deterministic sort axes with stable `id` tie breakers where needed.
9. Removed `get_weekly_review_snapshot` from MCP catalog and dispatch.
10. Removed `analyze_task_patterns` from MCP catalog, dispatch, guide text, and tests.
11. Replaced weekly review naming with `get_weekly_brief`.
12. Updated docs and tool descriptions to treat weekly brief as convenience context, not persisted review/reflection data.

Current status: no remaining implementation work for this design note.

## Non-Goals

Do not add a `weekly_reviews` table.

Do not add a user-authored weekly reflection record.

Do not keep multiple overlapping weekly context tools.

Do not rely on rule-based pattern analysis when flexible task history can support agent-side analysis.
