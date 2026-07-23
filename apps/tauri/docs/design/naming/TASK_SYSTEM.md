# Task System Naming

## Scope

This document defines naming for:

- tasks
- lists
- habits
- statuses
- priorities
- projects
- inbox
- today tasks vs overdue vs someday

## Current State In Code

### Tasks

Observed in:

- `lorvex-domain/src/naming/entity/`
- `lorvex-domain/src/naming/`
- `lorvex-store/src/repositories/task/`
- App/MCP/CLI task command surfaces

Canonical status values:

- `open`
- `completed`
- `cancelled`
- `someday`

### Lists

Observed in:

- `lorvex-domain/src/naming/entity/`
- App sidebar/list views
- CLI list commands
- MCP list tools

Current code reality:

- `list` is the canonical user-owned grouping entity
- list has visual metadata (`color`, `icon`) and descriptive metadata (`description`, `ai_notes`)

### Habits

Observed in:

- `lorvex-domain/src/naming/habit.rs`
- habit reminder policy entities
- habit completions edge

Current code reality:

- habit is its own first-class entity
- frequency types are:
  - `daily`
  - `weekly`
  - `custom`

### Inbox

Observed in code and docs:

- `lorvex-store/src/schema/001_schema.sql`
- `lorvex-domain/src/preference_keys/`
- setup/default-list routing
- tests that rely on the seeded default list
- `docs/design/PER_VIEW_CONTENT_STRATEGY.md`
- `docs/vision/*`

Current code/doc reality:

- the schema-seeded `inbox` default list remains so every fresh database has a concrete task target
- `default_list_id` is seeded to `inbox` as a bootstrap/default-routing artifact
- `inbox` may appear in schema, setup, tests, default-list routing, and historical docs
- `inbox` is not an active Inbox UI or review workflow
- conversation with the AI assistant replaces the old inbox-based review routing

## Canonical Terms

### Task

Canonical name:

- `task`

Meaning:

- the primary actionable work item

Do not create alternate canonical nouns like:

- `todo`
- `item`
- `action`

unless they are deliberately only UI copy.

### List

Canonical name:

- `list`

Meaning:

- human-visible grouping bucket for tasks

Use in UI:

- `List`
- list name

Avoid inventing synonyms like:

- `folder`
- `category`
- `bucket`

unless a specific UI copy moment absolutely needs one.

### Habit

Canonical name:

- `habit`

Meaning:

- repeatable personal practice tracked separately from task lifecycle

Avoid making habits sound like recurring tasks. They are related, not the same concept.

## Status Naming

### Canonical lifecycle statuses

- `open`
- `completed`
- `cancelled`
- `someday`

These are the canonical operator/domain values and should remain stable.

### UI wording

Human-facing copy may use:

- `Done` for `completed` in a button
- `Someday` for `someday`

But the canonical state names should remain unchanged in code and sync payloads.

## Priority Naming

Current code reality:

- priority is numeric
- lower numbers mean higher importance
- the canonical scale is three bands: `1`, `2`, `3`

Naming rule:

- use `priority` for the field
- use importance-framed copy, not urgency-framed copy
- do not create a second canonical scale noun like `urgency_rank`

## Projects

Current repo reality:

- there is no canonical `project` entity alongside `task` and `list`
- docs sometimes discuss projects conceptually

Final decision:

- `project` is currently a product-language concept, not a canonical domain entity
- do not describe lists as if they are formally projects
- do not describe inferred groupings as if they are first-class persisted projects

If projects become a real entity in the future, they should be introduced explicitly rather than quietly inferred from list language.

## Inbox

Final decision:

- `Inbox` is removed as a user-facing review surface and gating workflow
- the schema-seeded `inbox` default list is allowed as an internal bootstrap/default-routing artifact
- `inbox` may appear in schema, setup, tests, default-list routing, and historical docs
- do not reintroduce an Inbox view, status, staging area, triage queue, or review workflow

Use instead:

- `conversation`
- `AI assistant review layer`
- `quick capture`

depending on context

## Today / Overdue / Someday

These are different classes of concepts and should not be conflated.

### Today Tasks

Meaning:

- tasks from the today pool not already elevated into Today's Focus

This is a query/view bucket, not an entity.

### Overdue

Meaning:

- tasks with due date before today

This is also a query/view bucket, not an entity.

### Someday

Meaning:

- a canonical task lifecycle status

This is a true persisted lifecycle state, not merely a query bucket.

## Final Decision

The task-system vocabulary should be treated as:

- `task` = canonical work item
- `list` = canonical grouping entity
- `habit` = canonical repeat-practice entity
- `project` = product concept only, not canonical entity
- `Inbox` = removed user-facing review/gating surface
- `inbox` = internal seeded default-list artifact where schema/setup/default routing require it
- `today tasks` / `overdue` = query buckets
- `someday` = canonical task status
