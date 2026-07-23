# AI Notes Product Design

## Context

Lorvex is an AI-native task app: assistants are expected to create, update, plan,
defer, and annotate tasks and lists. That makes the old distinction between
"human-authored notes" and "AI-authored notes" less clear than it would be in a
traditional task app.

The question is whether `ai_notes` should exist at all, and if it does, what
product role it should play.

## Decision

Keep `ai_notes` for tasks and lists, but define it as the object's current
AI-maintained context panel, not as an append-only note history.

`ai_notes` should answer:

- What should a future assistant know before operating on this object?
- What recommendation, caveat, or reasoning is useful for the user to see?
- What context is helpful but not canonical enough to belong in the task body
  or list description?

It should not answer:

- What did the AI write every time it touched this object?
- What is the permanent audit trail?
- Which exact model/user/tool created each observation?

Those belong in changelog/activity/provenance surfaces.

## Product Model

`body` / `description` is canonical user-facing content. The user can edit it
directly, and it represents the task or list itself.

`ai_notes` is assistant-maintained context. It may contain suggestions, caveats,
operating instructions, or short reasoning that helps humans and future
assistants understand how to handle the object. Users should be able to inspect,
edit, and clear it, but they should not be required to maintain it.

Examples for task `ai_notes`:

- "Depends on the quarterly report; avoid scheduling before Friday."
- "User described this as low urgency but important for the launch checklist."
- "Consider splitting into design review and implementation if it remains open
  after two days."

Examples for list `ai_notes`:

- "Long-running infrastructure work. Do not mix quick personal errands here."
- "For this list, prefer weekly review over daily scheduling unless explicitly
  urgent."
- "Tasks here often require calendar blocks and should not be treated as quick
  captures."

## UI Direction

Tasks and lists should both have an Assistant Context section.

Recommended UI behavior:

- Render the field as Markdown.
- Keep it visually distinct from canonical task/list content.
- Default to read-only display with explicit edit and clear affordances.
- Hide or collapse the section when empty.
- Do not render it as a stack of timestamped note cards.
- Do not show every AI write as permanent object content.

The section should feel like a current-context summary, not a log.

## MCP/API Direction

The old `add_ai_notes` shape was not ideal because it implied append history
and prepended timestamped entries separated by `---`.

Preferred long-term tool semantics:

- `set_task_ai_notes(task_id, notes)`
- `set_list_ai_notes(list_id, notes)`

These should replace the current `ai_notes` block with the best current context.
The assistant is responsible for preserving anything still useful when it
updates the block.

If append semantics ever return, the tool name must make the scope explicit:

- `add_task_ai_note`, not generic `add_ai_notes`
- `add_list_ai_note`, if list append is intentionally supported

But the preferred product behavior is replace/maintain-current-summary rather
than append/prepend-history.

## Why Not A Stacked Note List

A structured stack of note entries is more complex than the current product
need. It creates extra concepts: entry author, entry timestamp, ordering,
single-entry deletion, conflict merging, and display density.

That complexity is useful for an activity log, not for object context. For
assistant usefulness, one current, maintained summary is usually better than a
growing trail of old observations.

## Relationship To Changelog

Use changelog/activity for provenance:

- what changed
- when it changed
- which tool performed it
- what the before/after state was

Use `ai_notes` for current operating context:

- why this object matters
- how to handle it
- what caveats future assistants should preserve

Do not use `ai_notes` as a substitute for auditability.

## Resolved Design Follow-Ups

- The user-facing task-detail label is now "Assistant Context" while the
  storage/API field remains `ai_notes`.
- Task UI renders assistant context as Markdown, read-only by default, and
  provides an explicit clear action. Empty context stays visually quiet.
- `ai_notes` remains searchable, but agents receive `match_reasons` from
  `search_tasks` so assistant-context-only hits are distinguishable from
  canonical title/body matches. The SQLite search path already ranks
  title/body above `ai_notes`.

## Design Review

The direction is sound: `ai_notes` should be a compact, current context surface,
not another event stream. Lorvex already has changelog/activity/provenance
concepts for history; using the object field as an append-only log would create
duplicated audit surfaces and eventually make the task detail harder to scan.

The main product correction was naming. "AI Notes" is understandable to
developers, but it can imply "notes written by AI" or "a log of AI thoughts."
The user-facing label is now "Assistant Context"; the storage field remains
`ai_notes` because the field is intentionally not canonical task content.

There is one ownership boundary: the document says users should be able to
inspect and clear the field, while the implementation and tool
copy currently describe it as assistant-maintained and never human-editable.
Those are different product models. The cleaner model is:

- Humans can always inspect and clear assistant context.
- Humans can edit canonical task/list content in `body` / `description`.
- Direct human editing of assistant context should be an explicit advanced
  affordance, not the normal notes workflow.

Search also needs a product decision. It is reasonable for assistant context to
participate in search, but matches should rank below title/body matches and the
UI should avoid making AI-context-only hits look like canonical task matches.
When a result only matched `ai_notes`, the result row should expose that reason.

Finally, anything in `ai_notes` must be treated as untrusted object content when
sent back to assistants. It may have been generated from user-controlled input
or stale assistant output, so it cannot become policy, authority, or hidden
instruction. The existing content fencing direction remains important here.

## Implemented Design Changes

- Replaced task MCP `add_ai_notes` with `set_task_ai_notes(task_id, notes)`.
- Added list MCP `set_list_ai_notes(list_id, notes)`.
- Empty `notes` clears the assistant context block.
- Renamed the service/store task write path from `addTaskAINotes` to
  `setTaskAINotes`.
- Removed timestamp prepend / `---` merge behavior from the task AI notes write
  path.
- Removed the Shortcuts/App Intents action that directly wrote task AI notes.
- Removed the task-detail store action for manually appending AI notes from the
  app UI.
- Updated batch deferral so free-text reasons are returned as transient
  `defer_note` output and are no longer appended into `ai_notes`; structured
  reasons continue to persist in `last_defer_reason`.
- Added task-detail clear behavior for assistant context without adding a
  normal human edit flow.
- Added `match_reasons` to `search_tasks` rows, including `ai_notes`, so agents
  can identify assistant-context-only matches.
- Added regression coverage for set/clear behavior, batch-deferral non-append
  behavior on preview and live-core paths, search match reasons, and Markdown
  export labeling.

## Remaining Implementation TODO

None for the current product decision. Future work should be driven by a new
product requirement, not by treating `ai_notes` as an unfinished append-log
surface.
