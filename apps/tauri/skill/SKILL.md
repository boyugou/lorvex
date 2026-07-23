---
name: lorvex
description: "AI-native structured planning with Lorvex. Use when: (1) user asks to plan, schedule, or organize tasks (2) user mentions task management, daily review, or focus planning (3) user wants to capture ideas, defer work, or track progress (4) user says 'what should I work on' or asks about priorities (5) user wants to review what was accomplished"
version: 1.0.0
user-invocable: true
metadata:
  openclaw:
    emoji: "📋"
    homepage: https://github.com/boyugou/lorvex
    requires:
      anyBins:
        - lorvex
    primaryEnv: ""
---

# Lorvex — AI-Native Structured Planning

Lorvex is an AI-native personal planning system. You are the planning intelligence — Lorvex is your structured substrate for tasks, lists, focus, reviews, memory, and scheduling.

## How You Connect

Lorvex exposes 117 MCP tools via `lorvex mcp serve`. If the MCP server is already configured, you have direct tool access. If not, guide the user through setup.

### Check if Lorvex is available

```bash
lorvex --format json doctor
```

If this fails, the user needs to install Lorvex CLI:

```bash
# From source
git clone https://github.com/boyugou/ai-native-todo
cd ai-native-todo && bash scripts/install_cli.sh
```

Homebrew packaging is planned but not published yet; do not suggest
`brew install lorvex` until the distribution docs mark that channel as
shipped.

### Configure MCP

```bash
lorvex mcp install --for claude-code
# or: lorvex mcp install --for claude-desktop
# or: lorvex mcp install --for codex
```

After install, restart your session so the MCP tools become available.

## Core Workflow

### 1. Session Start

Always begin by calling `get_session_context` to understand the current state:
- What tasks are open, overdue, or due today
- What today's focus plan is
- What memory you have about the user's preferences
- Recent AI changelog (what you did last time)

### 2. Planning Conversations

When the user discusses what to work on:
1. Call `get_todays_tasks` to see what's on the plate
2. Call `get_overview` for the full picture (lists, priorities, streaks)
3. Suggest a focus plan via `set_current_focus` with a briefing
4. Create tasks with `create_task` — set priority, due dates, estimates
5. Use `write_memory` to store user preferences and patterns you learn

### 3. Task Lifecycle

- **Create**: `create_task` with title, priority (1-3), due_date, estimated_minutes, list_id, tags
- **Update**: `update_task` for any field changes (priority, due_date, body, status, etc.)
- **Complete**: `complete_task` — auto-spawns next recurrence if recurring
- **Defer**: `defer_task` with structured reason (not_today, blocked, low_energy, needs_breakdown, needs_info)
- **Cancel**: `cancel_task` — removes from active work
- **Batch**: `batch_update_tasks` for bulk operations

### 4. Daily Review

At end of day or when asked:
1. Call `get_weekly_review_brief` for completed/stalled/deferred summary
2. Create a daily review with `add_daily_review` (summary, mood, energy, wins, blockers, learnings)
3. Use `analyze_task_patterns` to surface recurring deferral or stalled lists
4. Update `write_memory` with any new patterns you've learned

### 5. Focus Planning

- `set_current_focus` — set today's focus tasks with a briefing
- `propose_daily_schedule` — generate time-blocked schedule based on working hours and calendar
- `save_focus_schedule` — persist the schedule

### 6. Memory

Store what you learn about the user:
- `write_memory` — save preferences, working patterns, project context
- `read_memory` — recall stored context before making recommendations
- `notes_for_ai` is user-authored context. Read it through session/memory
  surfaces, but do not write it through MCP; ask the user to edit it in the app
  when it needs to change.

## Key MCP Tools Reference

### Queries
| Tool | Purpose |
|------|---------|
| `get_session_context` | Everything you need at session start |
| `get_overview` | Full dashboard: stats, lists, top tasks |
| `get_todays_tasks` | Today's task pool |
| `get_upcoming_tasks` | Next N days |
| `search_tasks` | Full-text search across all tasks |
| `get_list` | Tasks in a specific list |
| `get_weekly_review_brief` | Weekly review data |
| `get_guide` | Contextual guidance based on current state |

### Mutations
| Tool | Purpose |
|------|---------|
| `create_task` | Create a new task |
| `update_task` | Modify any task field |
| `complete_task` | Mark done (spawns recurrence if applicable) |
| `defer_task` | Reschedule with structured reason |
| `batch_update_tasks` | Bulk modify multiple tasks |
| `set_current_focus` | Set today's focus plan |
| `write_memory` | Store AI memory |
| `add_daily_review` | Create/update daily review |

### Calendar
| Tool | Purpose |
|------|---------|
| `create_calendar_event` | Schedule meetings, blocks |
| `get_calendar_events` | Query events in a date range |
| `propose_daily_schedule` | AI-generated time blocks |

## Design Principles

1. **You are the intelligence, Lorvex is the substrate.** Don't just read and report — actively plan, prioritize, and suggest.
2. **Every write logs to ai_changelog.** The user can always see what you changed and why.
3. **Priority is AI-managed.** Use the 3-band importance-first model: `1` = top importance, `2` = important, `3` = background. Time pressure should come from due dates, planned dates, and focus decisions.
4. **Rich return values.** Every MCP tool returns the complete updated object — use it to confirm changes.
5. **Duration estimation matters.** Set `estimated_minutes` to enable scheduling.
6. **ai_notes is private task context.** Use it for details the user doesn't need to see in the visible title or notes.

## CLI Fallback

If MCP is not available, you can use the CLI directly:

```bash
lorvex --format json today      # Today's tasks
lorvex capture "Buy milk"       # Quick task creation
lorvex complete <task-id>       # Complete a task
lorvex --format json focus      # Current focus
lorvex --format json doctor     # System health
```

Use the global `--format json` option for structured CLI output.
