# RFC-001: Database Layer

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


*Status: IMPLEMENTED — SQLite schema, WAL mode, migrations, dual-access all shipped*

---

> Historical snapshot: this RFC was written during the Node-to-Rust MCP transition. Mentions of a Node.js MCP process or `better-sqlite3` capture the design state at authoring time; the shipped MCP runtime is Rust-only. Current implementation truth lives in `docs/design/ARCHITECTURE.md` and `docs/reference/REPO_FACTS.md`.

## Problem

Both the MCP runtime and the Tauri app (Rust + WebView) need to read/write the same SQLite database. At authoring time the MCP side was still being specified from a Node.js baseline. We need to decide:

1. Where the database file lives
2. How concurrent access is handled safely
3. How schema migrations work
4. Which SQLite library each process uses

---

## Option A: Shared Path via Convention (Accepted)

Both processes assume a fixed, conventional path:

```
~/Library/Application Support/Lorvex/db.sqlite
```

The MCP server binary defaults to this path but accepts `--db` flag or `DB_PATH` env var to override.

**Why:** Simplest. No coordination needed. Standard macOS app convention. The user can override if needed via `claude_desktop_config.json` env vars.

**Why not:** Hardcoded app name means rename = breakage. Acceptable risk for now.

## Option B: Config File Rendezvous (Rejected)

App writes `~/.config/lorvex/config.json` with the DB path; MCP server reads it.

**Why rejected:** Adds a file-system coordination layer. Creates a race condition on first launch (app might not have written config yet when MCP connects). Complexity without proportional benefit.

## Option C: User Specifies Path in MCP Config (Rejected as primary)

User manually sets `DB_PATH` in `claude_desktop_config.json`. Kept as an override mechanism, not the default.

**Why rejected as primary:** Puts burden on the user. Defeats the goal of easy setup.

---

## Decision: Option A + Option C as override

```
Default: ~/Library/Application Support/Lorvex/db.sqlite
Override: DB_PATH env var or --db flag
```

---

## Concurrency Model

Both processes write to the same file. SQLite handles this via WAL mode.

### Settings (applied once on connection open)

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;   -- safe with WAL, faster than FULL
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;    -- wait up to 5s if locked, then error
PRAGMA cache_size = -8000;     -- 8MB cache (negative = KB)
```

### Write Conflict Reality

- MCP server is the heavy writer (Claude operations)
- Tauri app writes for human actions (complete, defer, edit)
- Both are event-driven, not continuous streams
- Conflicts are rare in practice; busy_timeout=5000 covers the edge cases
- No custom locking needed

---

## Migration System

### Schema Version Tracking

```sql
CREATE TABLE IF NOT EXISTS migrations (
  version     INTEGER PRIMARY KEY,
  applied_at  TEXT NOT NULL,
  description TEXT
);
```

### Migration Execution

On process startup:
1. Create `migrations` table if it doesn't exist
2. Query max(version) from migrations
3. Apply any SQL files with version > current
4. Each migration runs in a transaction — if it fails, rollback and abort startup

### File Naming Convention

```
db/migrations/
  001_initial_schema.sql
  002_add_someday_status.sql
  003_add_current_focus.sql
```

Migrations are embedded in both the MCP server binary and the Tauri app. **First writer wins** — if both start simultaneously, one will create the tables and insert into migrations; the other will see the up-to-date version and skip. This is safe because migrations use `CREATE TABLE IF NOT EXISTS`.

### Shared Migration Files

Since both MCP server and Tauri app need migrations, the SQL files live in:

```
shared/
  db/
    migrations/
      001_initial_schema.sql
      ...
    schema.ts          # TypeScript types matching the schema
```

In the original TypeScript sketch, the MCP server imported from `../shared/db/`. The Tauri app embeds the SQL files at compile time.

---

## SQLite Libraries

| Process | Library | Why |
|---|---|---|
| MCP runtime candidate (Node.js at authoring time) | `better-sqlite3` | Synchronous, fastest Node.js SQLite, mature |
| Tauri App (Rust) | `rusqlite` directly | Lower level, fine control, no ORM overhead |

**Why not `tauri-plugin-sql`?** It exposes SQL to the frontend (JavaScript), which is convenient but:
- Exposes raw SQL to the WebView (security surface)
- Less control over connection lifecycle
- We want Rust commands to own all DB logic; the frontend calls Tauri commands, never raw SQL

**Why `better-sqlite3` over `sql.js` or `@libsql/client`?**
- `better-sqlite3` is synchronous (no async complexity in MCP handlers)
- Fast (direct C binding, no JSON serialization overhead)
- Battle-tested (SQLite expert mode)
- `sql.js` = in-memory only. `@libsql/client` = libSQL dialect, overkill.

---

## TypeScript Schema Types

The `shared/` package exports TypeScript types that match the DB schema. Both the MCP server and (eventually) a TypeScript config layer in Tauri can import these.

```typescript
// shared/src/types.ts
export interface Task {
  id: string;
  title: string;
  body: string | null;
  raw_input: string | null;
  ai_notes: string | null;
  status: 'open' | 'completed' | 'cancelled' | 'deferred' | 'inbox' | 'someday';
  list_id: string | null;
  tags: string | null; // JSON array
  priority: 1 | 2 | 3 | 4 | null;
  urgency_score: number | null;
  is_pinned: 0 | 1;
  due_date: string | null; // YYYY-MM-DD
  due_time: string | null; // HH:MM
  estimated_minutes: number | null;
  actual_minutes: number | null;
  reminder_at: string | null; // ISO 8601 UTC
  recurrence: string | null; // JSON
  depends_on: string | null; // JSON array — single truth source for dependencies
  // blocks, sort_order, confidence removed — see current schema
  context_ref: string | null; // JSON
  created_at: string; // ISO 8601
  updated_at: string;
  completed_at: string | null;
  last_deferred_at: string | null;
  defer_count: number;
}

export interface TaskList {
  id: string;
  name: string;
  color: string | null;
  icon: string | null;
  description: string | null;
  ai_notes: string | null;
  created_at: string;
  sort_order: number | null;
}

export interface AIChangelogEntry {
  id: string;
  timestamp: string;
  operation: string;
  entity_type: string;
  entity_id: string | null;
  entity_ids: string | null;
  summary: string;
  before_state: string | null;
  after_state: string | null;
  initiated_by: string; // 'human' or any AI agent identity
  mcp_tool: string | null;
  is_undone: 0 | 1;
  undone_at: string | null;
  undone_by: string | null;
}

export interface CurrentFocus {
  date: string; // YYYY-MM-DD
  task_ids: string; // JSON array
  briefing: string | null;
  created_at: string;
  modified_at: string;
}

export interface UserPreference {
  key: string;
  value: string; // JSON
  updated_at: string;
}
```

---

## Open Questions Resolved

**Q: Should we use an ORM (Drizzle, Kysely)?**
A: No. The schema is stable and well-defined. Raw SQL is more predictable, easier to debug, and avoids abstraction overhead. We'll use parameterized queries directly.

**Q: Should we use a connection pool?**
A: No. `better-sqlite3` is synchronous — one connection per process is correct. SQLite with WAL handles concurrent processes without a pool.

**Q: How do we handle the DB path on first run before the Tauri app creates it?**
A: The MCP server also creates the DB (and runs migrations) if it doesn't exist. First writer creates and migrates; second writer detects up-to-date schema and proceeds. Both can initialize safely.
