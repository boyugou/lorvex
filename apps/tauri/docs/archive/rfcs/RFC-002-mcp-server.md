# RFC-002: MCP Server Architecture

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


*Status: IMPLEMENTED — stdio transport, modular tool groups (current inventory in `docs/design/MCP_TOOLS.md`)*

---

> Historical snapshot: this RFC preserves the original TypeScript package-layout sketch used during the Rust migration. The shipped MCP runtime is Rust-only; current implementation truth lives in `docs/design/MCP_TOOLS.md`, `docs/design/ARCHITECTURE.md`, and `docs/reference/REPO_FACTS.md`.

## Problem

Design the MCP server so that:
1. It exposes all planned tools to Claude Desktop
2. It's maintainable (tools organized logically)
3. It produces a distributable binary
4. It handles errors gracefully and always writes to ai_changelog
5. Claude can use it with minimal guidance (self-documenting tool descriptions)

---

## Historical Package Structure at Authoring Time

```
mcp-server/
  src/
    index.ts          # Entry point: create server, register all tools, connect stdio
    db.ts             # Database connection singleton + migration runner
    changelog.ts      # Shared helper: write to ai_changelog
    urgency.ts        # Urgency score computation (shared logic)
    tools/
      tasks.ts        # create_task, update_task, complete_task, cancel_task, permanent_delete_task, get_task,
                      # list_tasks, search_tasks, batch_*, add_ai_notes
      lists.ts        # create_list, update_list, list_all_lists, get_list
      daily.ts        # set_current_focus, get_current_focus, clear_current_focus
      context.ts      # get_overview, get_weekly_review_brief, get_todays_tasks,
                      # get_upcoming_tasks, propose_daily_schedule
      preferences.ts  # set_preference, get_preference, get_all_preferences
  package.json
  tsconfig.json
```

**Why not a single giant file?** Tools will be ~500-800 lines each at full implementation. A single file becomes unmaintainable. Splitting by domain (tasks, lists, context) matches the mental model.

**Why no ORM?** The schema is defined once and stable. Raw SQL with parameterized queries is faster, more transparent, and avoids abstraction impedance. We use TypeScript types from `shared/` to stay type-safe.

---

## Tool Registration Pattern

Each tool file exports a `register*Tools(server, db)` function:

```typescript
// tools/tasks.ts
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import Database from 'better-sqlite3';
import { logChange } from '../changelog.js';
import { computeUrgencyScore } from '../urgency.js';

export function registerTaskTools(server: McpServer, db: Database.Database) {
  server.registerTool(
    'create_task',
    {
      title: 'Create Task',
      description: `Create a new task.

Use when the user explicitly requests a task, or when you identify an actionable
commitment from conversation.

Always provide:
- title: clear, actionable, starts with a verb
- raw_input: original user text that led to this task
- ai_notes: your reasoning for creating it

Returns the complete task object. No follow-up get call needed.`,
      inputSchema: z.object({
        title: z.string().describe('Task title, clear and actionable'),
        list_id: z.string().optional().describe('ID of list to assign to. Omit to use default list.'),
        priority: z.number().int().min(1).max(4).optional()
          .describe('1=urgent 2=high 3=medium 4=low'),
        due_date: z.string().optional().describe('YYYY-MM-DD'),
        due_time: z.string().optional().describe('HH:MM (24h)'),
        estimated_minutes: z.number().int().positive().optional()
          .describe('Estimated time to complete'),
        tags: z.array(z.string()).optional(),
        body: z.string().optional().describe('Markdown notes'),
        raw_input: z.string().optional()
          .describe('Original natural language input. Always include when task comes from conversation.'),
        ai_notes: z.string().optional()
          .describe('Your reasoning, observations, or context for this task.'),
        to_inbox: z.boolean().optional().default(false)
          .describe('Route to inbox for human approval'),
      }),
    },
    async (args) => {
      // Implementation
    }
  );
}
```

---

## Error Handling Convention

All tool handlers follow this pattern:

```typescript
async (args) => {
  try {
    // ... implementation
    return {
      content: [{ type: 'text', text: JSON.stringify(result) }]
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: 'text', text: `Error: ${message}` }],
      isError: true
    };
  }
}
```

**Never throw from a tool handler.** Return `isError: true` so Claude can handle it gracefully.

---

## Changelog Writing Convention

Every write operation calls `logChange()`:

```typescript
// changelog.ts
export function logChange(db: Database.Database, params: {
  operation: string;
  entity_type: 'task' | 'list' | 'schedule' | 'preference';
  entity_id?: string;
  entity_ids?: string[];
  summary: string;
  before_state?: unknown;
  after_state?: unknown;
  mcp_tool: string;
}) {
  db.prepare(`
    INSERT INTO ai_changelog
      (id, timestamp, operation, entity_type, entity_id, entity_ids,
       summary, before_state, after_state, initiated_by, mcp_tool)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ai', ?)
  `).run(
    randomUUID(),
    new Date().toISOString(),
    params.operation,
    params.entity_type,
    params.entity_id ?? null,
    params.entity_ids ? JSON.stringify(params.entity_ids) : null,
    params.summary,
    params.before_state ? JSON.stringify(params.before_state) : null,
    params.after_state ? JSON.stringify(params.after_state) : null,
    params.mcp_tool,
  );
}
```

The `summary` must be human-readable. This is what the user sees in AI Activity. Examples:
- ✓ `"Created task 'Write intro section' in Paper list, due Friday"`
- ✓ `"Marked 'Review Q3 budget' as completed"`
- ✓ `"Moved 3 tasks to high priority based on Friday deadline"`
- ✗ `"create_task called"` (useless)
- ✗ `"Task updated"` (no context)

---

## Urgency Score Computation

Historical TypeScript-side note at authoring time (the shipped Rust runtime now owns this logic):

```typescript
// shared/src/urgency.ts
export function computeUrgencyScore(task: {
  due_date: string | null;
  priority: number | null;
  defer_count: number;
  blocks: string | null;
  is_pinned: 0 | 1;
}): number {
  if (task.is_pinned) {
    const priorityBase: Record<number, number> = { 1: 2.0, 2: 1.5, 3: 1.0, 4: 0.5 };
    return priorityBase[task.priority ?? 3] ?? 1.0;
  }

  let score = 0;

  if (task.due_date) {
    const now = new Date();
    const due = new Date(task.due_date + 'T23:59:59');
    const daysUntil = (due.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);
    if (daysUntil < 0) score += 10;
    else if (daysUntil < 1) score += 7;
    else if (daysUntil < 2) score += 5;
    else if (daysUntil < 3) score += 3;
    else if (daysUntil < 7) score += 1.5;
    else score += 0.5;
  }

  // Reverse dependency count (tasks blocked by this one) would be derived
  // at read time from other tasks' depends_on — not stored on the task.

  score += Math.log1p(task.defer_count) * 0.8;

  const priorityBase: Record<number, number> = { 1: 2.0, 2: 1.5, 3: 1.0, 4: 0.5 };
  score += (priorityBase[task.priority ?? 3] ?? 1.0) * 0.5;

  return Math.round(score * 100) / 100;
}
```

---

## Build & Distribution

### Development
```bash
cargo run --manifest-path mcp-server/Cargo.toml
```

### Production
```bash
cargo build --manifest-path mcp-server/Cargo.toml --release
./mcp-server/target/release/lorvex-mcp-server
```

> Historical RFC note: this RFC originated as a Node/TypeScript MCP plan. The current runtime truth is the Rust binary `lorvex-mcp-server` under `mcp-server/`; the old Node `dist/index.js` path is retired.

### Distribution Binary (for bundling with app)
Option A: bundle the Rust standalone binary with the app resources
Option B: prepare the same Rust binary into `mcp-server/bin/` for source-checkout development

**Current decision:** ship `lorvex-mcp-server` as the only supported runtime. Avoid dual-runtime packaging and point MCP clients at the Rust binary directly.

The retired Tauri App Store packaging path is intentionally not supported. Point MCP clients at the supported Rust binary path for the active distribution channel.

### claude_desktop_config.json Entry
```json
{
  "mcpServers": {
    "lorvex": {
      "command": "/path/to/lorvex/mcp-server/bin/lorvex-mcp-server",
      "args": [],
      "env": {
        "DB_PATH": "~/Library/Application Support/Lorvex/db.sqlite"
      }
    }
  }
}
```

---

## What This RFC Deliberately Excludes

- WebSocket/HTTP transport (stdio only, per MCP convention)
- Authentication (local process, no auth needed)
- Rate limiting (local process, Claude calls are infrequent)
- Caching (better-sqlite3 is fast enough, SQLite has built-in page cache)
- Streaming responses (not needed for tool calls)
