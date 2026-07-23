# Planning Naming

## Scope

This document defines the canonical naming for:

- today pool
- current focus
- focus schedule
- daily review
- weekly review
- briefing
- rationale

## Current State In Code

### Today Pool

Observed in:

- `app/src-tauri/src/commands/overview.rs`
- `mcp-server/src/tasks/day_query/today.rs`
- `docs/design/PER_VIEW_CONTENT_STRATEGY.md`

Meaning in code:

- open tasks with `planned_date <= today`
- or tasks with `planned_date IS NULL && due_date <= today`
- plus separate overdue and high-priority undated handling in some MCP views

This is clearly a candidate pool, not a committed plan.

### Current Focus

Observed in:

- `mcp-server/src/focus/current/`
- `app/src-tauri/src/commands/planning/current_focus.rs`
- `docs/design/DATA_MODEL.md`
- `docs/design/UX.md`

Meaning in code:

- a date-keyed, ordered subset of tasks
- carries `briefing`
- powers the Today view's top section
- is explicitly AI-curated

This is the real daily commitment layer.

### Focus Schedule

Observed in:

- `mcp-server/src/focus/schedule/`
- `app/src-tauri/src/commands/planning/focus_schedule.rs`
- `lorvex-store/src/focus_schedule_snapshot.rs`
- `docs/design/DATA_MODEL.md`

Meaning in code:

- a date-keyed set of schedule blocks
- carries `rationale`
- only schedules tasks already present in current focus
- saving a focus schedule also syncs schedule task order back into `current_focus_items`

This is a time-blocked execution layer, not a task-selection layer.

### Daily Review

Observed in:

- `app/src-tauri/src/commands/reviews.rs`
- `mcp-server/src/reviews/daily/`
- `docs/design/DATA_MODEL.md`

Meaning in code:

- an end-of-day reflection entry
- separate from focus and schedule
- can link tasks and lists

### Weekly Review

Observed in:

- `app/src-tauri/src/commands/reviews.rs`
- `mcp-server/src/reviews/weekly/`

Meaning in code:

- a derived review artifact / brief
- not a first-class persisted aggregate like `daily_review`

## Canonical Model

Lorvex should use this three-layer planning model:

### 1. Today Pool

Definition:

- the candidate set of tasks relevant to today

Role:

- discovery layer
- not a commitment
- not a schedule

Canonical name:

- `today_pool`

UI language:

- `Today Tasks`
- `Today`

### 2. Today's Focus

Definition:

- the selected ordered set of tasks that the user and AI treat as today's real plan

Role:

- commitment layer
- the core of the day plan

Canonical domain name:

- `current_focus`

Preferred UI/product label:

- `Today's Focus`

Allowed operator wording:

- `current_focus`

Avoid:

- `daily_schedule`
- `current task`
- `today_schedule`

### 3. Focus Schedule

Definition:

- the time-blocked arrangement of the tasks already in Today's Focus

Role:

- temporal execution layer
- not a selection mechanism

Canonical name:

- `focus_schedule`

UI/product label:

- `Focus Schedule`

Avoid:

- making it sound like the whole-day canonical plan
- using it as a synonym for `current_focus`

## Umbrella Term

Allowed umbrella terms:

- `Day Plan`
- `Today Plan`

These terms are product language only.

They refer to:

- Today's Focus
- plus optional Focus Schedule

They do not imply a new entity/table/tool family.

## Briefing vs Rationale

These are currently distinct in code and should stay distinct.

### Briefing

Belongs to:

- `current_focus`

Meaning:

- why these tasks matter today
- AI's note for the day

### Rationale

Belongs to:

- `focus_schedule`

Meaning:

- why this time arrangement was chosen

Do not merge these into a single generic `reason`.

## Review Naming

### Daily Review

Canonical name:

- `daily_review`

Meaning:

- reflective end-of-day record
- not part of the day plan itself

### Weekly Review

Canonical product concept:

- `weekly_review`

Meaning:

- summary / analysis layer over recent tasks, lists, deferrals, and daily reviews

Current code reality:

- more derived/query-driven than entity-driven

## Recommended UI Terms

Use:

- `Today's Focus`
- `Today Tasks`
- `Focus Schedule`
- `Daily Review`
- `Weekly Review`

Gradually phase down:

- `Current Focus` as the primary user-facing label

Keep internally:

- `current_focus`

## MCP / CLI Wording

### Keep canonical internal tool family

Allowed tool-family wording:

- `get_current_focus`
- `set_current_focus`
- `add_to_current_focus`
- `clear_current_focus`
- `save_focus_schedule`

### Legacy action phrase

`propose_daily_schedule` currently exists and should be treated as:

- a compatibility action name
- not proof that `daily_schedule` is the canonical domain concept

In docs/tool descriptions, explain it as:

- propose a focus schedule for today's focus

## Final Decision

The planning naming system should be treated as:

- `today_pool` = candidate pool
- `current_focus` = canonical daily commitment entity
- `Today's Focus` = preferred human-facing label for `current_focus`
- `focus_schedule` = time-blocked execution layer
- `Day Plan` / `Today Plan` = umbrella product language
- `daily_schedule` = legacy action phrase only, not canonical concept
