# Command Palette & Search (⌘K)
The command palette is the power-user backbone of the app. It replaces toolbars, menus, and most navigation. In an app this minimal, ⌘K must be capable enough that a keyboard-driven user never needs to reach for the mouse.

---

## Design Philosophy

The command palette solves a tension: the UI is radically simple (few buttons, few controls), but users still need access to the full action space. ⌘K is the answer — **all actions are one keystroke away, but none of them clutter the interface.**

Design targets:
- **Instant, keyboard-first feel** — the palette opens and responds with no perceptible latency.
- **Fast fuzzy matching** — partial, out-of-order queries resolve to the right result.
- **Context awareness** — surface the actions relevant to the current view first.
- **Categorized actions** — group a large action set so it stays scannable as it grows.

---

## Anatomy

```
┌──────────────────────────────────────────────────────────┐
│  ⌘K  Search tasks or run a command...                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Recent                                                  │
│  ○  Write intro section                  Paper · Mar 1   │
│  ○  Review PR #287                       Work · Today    │
│                                                          │
│  Quick Actions                                           │
│  ▸  New Task                                       ⌘N   │
│  ▸  Go to Today                                    ⌘1   │
│  ▸  Go to Upcoming                                  ⌘2   │
│  ▸  Go to All Tasks                                ⌘3   │
│  ▸  Go to AI Activity                              ⌘4   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

On open: shows navigation targets + quick actions. As you type, results filter in real-time.

## Implementation Status

The palette has a shipped core and a planned expansion:

**Implemented now**
- Global navigation targets (Today/Upcoming/All/Settings/etc.)
- List navigation targets
- Task search (starts at 2+ characters)
- Open task detail with `Enter`
- Task quick actions on selected task result:
  - `⌘/Ctrl + Enter` complete (or reopen if already completed/cancelled)
  - `Alt + Enter` defer
  - `Shift + Enter` cancel (soft delete)
- Quick-create task from query text when no results are found
- `@` prefix scoped list mode:
  - List navigation and filtering (`@work`)
  - Scoped quick capture (`@work::task title` creates a task in the matched list)
  - List shelving to someday (`⌘/Ctrl + Enter` on matched list)
  - List deletion (`Shift + Enter` on matched list)
  - Create new list when no match found
- Move-to-list via `Tab` key on a selected task result (enters list picker mode)
- List deletion from search results
- System actions from `app/src/components/command-palette/controller/systemActions.logic.ts`

**Planned**
- Additional prefix-scoped modes (`>`, `#`, `!`, `?`)
- Contextual command families for bulk operations

---

## Search Modes

### Default: Everything
Type anything → full-text search across:
1. Task titles (weighted highest via BM25)
2. Task body/notes
3. AI notes
4. List names (client-side filter)
5. Command names (client-side filter)

Results are ranked by task status (open first), then BM25 relevance, then recency.

### Scoped Search
Prefix triggers for faster targeting:

| Prefix | Scope | Example | Status |
|---|---|---|---|
| (none) | Everything | `paper intro` | Shipped |
| `@` | Lists (navigate, capture, shelve, delete, create) | `@work`, `@work::buy milk` | Shipped |
| `>` | Commands only | `>new task` | Planned |
| `#` | Tags | `#urgent` | Planned |
| `!` | Overdue tasks | `!` (shows all overdue) | Planned |
| `?` | AI notes search | `?blocks friday` | Planned |

### Search Result Types

```
Searching: "barcelona"

Tasks (2)
  ○  Confirm Barcelona hotel booking      Personal · Mar 3 · ●●
  ○  Book Barcelona flights               Spain · Mar 10 · ●●

Lists (1)
  ● Spain Trip                             4 tasks

AI Activity (1)
  Created 3 tasks from Spain trip conversation   Feb 28 09:14
```

Each result type has a distinct visual treatment. Tasks are interactable (click to open detail). Lists navigate to the list view. Changelog entries link to the affected tasks.

---

## Command Set

### Shipped Command Families

| Family | Shortcut(s) | Scope |
|---|---|---|
| Navigation jump | `⌘/Ctrl+1..5`, `Enter` | App-level views + lists |
| Quick capture | `⌘/Ctrl+N` (global), create-from-query action in palette | Task creation |
| Open task | `Enter` on task result | Task detail |
| Complete / reopen task | `⌘/Ctrl+Enter` on task result | Task write action |
| Defer task | `Alt+Enter` on task result | Task write action |
| Cancel task (soft delete) | `Shift+Enter` on task result | Task write action |
| Move task to list | `Tab` on task result, then select list | Task write action |
| `@` list scope mode | `@` prefix in query | List navigation, scoped capture, shelve, delete, create |
| Delete list | `Shift+Enter` on list result (in search or `@` mode) | List write action |
| Shelve list to someday | `⌘/Ctrl+Enter` on list in `@` mode | List write action |

### Shipped System Actions

These palette-level actions are backed by `systemActions.logic.ts`. That
registry is the implementation source of truth; this list is the product/docs
mirror.

| ID | Action |
|---|---|
| `system.syncNow` | Sync now |
| `system.exportData` | Export data |
| `system.importData` | Import data |
| `system.openDailyReview` | Open Daily Review |
| `system.createHabit` | Create habit |
| `system.completeHabit` | Complete habit |
| `system.moveTaskHint` | Show move-task hint |
| `system.toggleLanguage` | Toggle language |
| `system.cycleTheme` | Cycle theme |
| `system.openShortcuts` | Open keyboard shortcuts |
| `system.permanentDeleteTask` | Permanently delete selected task |
| `system.purgeCancelled` | Purge cancelled tasks |
| `system.resetSyncRetries` | Reset sync retries |
| `system.deleteAllData` | Open Delete All Data flow |

### Planned Command Families

- Additional prefix-scoped modes (`>commands`, `#tags`, `!overdue`, `?ai-notes`)
- View-scoped write commands

---

## Interaction Flow

1. Press ⌘K → palette appears
2. Start typing → results filter in real-time
3. `↑↓` to navigate results
4. `Enter` opens selected item (view or task)
5. On a selected task result: `⌘/Ctrl+Enter`, `Alt+Enter`, `Shift+Enter` run quick actions
6. `Esc` dismisses palette

The palette must feel INSTANT. No loading spinners. SQLite full-text search is local and fast — there is no reason for any perceptible delay. The search query uses `keepPreviousData` (TanStack Query) to hold the previous result set while a new query is in-flight, preventing flicker during rapid typing.

---

## Search Implementation

Task search runs **server-side via Tauri IPC** (`search_tasks` command), backed by SQLite FTS5 full-text search:

- **FTS5 with BM25 ranking**: The `tasks_fts` virtual table indexes title, body, ai_notes, and aggregated tag display_names (#2574). Results are ranked by `bm25(tasks_fts, 10.0, 1.0, 0.5, 3.0)` — title matches weighted 10×, body 1×, ai_notes 0.5×, tags 3×.
- **Prefix matching on the last token**: The query sanitizer (`sanitize_fts_query`) quotes each token and appends a `*` wildcard to the last token for type-ahead matching. E.g., `"buy gro"` becomes `"buy" "gro"*`, matching "buy groceries".
- **Status-aware ranking**: Open tasks rank above someday, which rank above completed/cancelled, via `CASE WHEN t.status = 'open' THEN 0 WHEN t.status = 'someday' THEN 1 ELSE 2 END` in the ORDER BY clause. Within each status tier, BM25 relevance and `updated_at` recency break ties.
- **LIKE fallback**: If the FTS query is empty after sanitization (e.g., all special characters) or the FTS table is unavailable, search falls back to `LIKE` on title, body, ai_notes, and tag names.

List and navigation matching uses client-side `String.includes()` filtering — only task search goes through FTS5.

---

## Contextual Awareness

The command palette adapts to context:

- **In Today view**: "Defer" commands use smart defaults (tomorrow, next week)
- **In List view**: "New Task" pre-fills the current list
- **In All Tasks**: status-specific actions appear as quick actions
- **When a task is selected**: task-specific actions appear at the top

---

## Why This Matters

In an app with minimal chrome, the command palette is the primary affordance for discoverability. New users learn the app by exploring ⌘K. Power users never leave it.

The palette also serves as the app's "API surface" for humans — everything the app can do is listed here. This parallels how the MCP tools are the "API surface" for AI assistant. Two interfaces, same capabilities, different users.
