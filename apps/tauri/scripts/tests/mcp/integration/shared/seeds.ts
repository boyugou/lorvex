import Database from 'better-sqlite3';
import { randomUUID } from 'crypto';

import { daysFromTodayYmd } from './time';

// Canonical 28+ char HLC for fixture seeding. Matches the Rust
// `TEST_VERSION` constant in `lorvex-domain/src/hlc.rs:196`
// (`0000000000000_0000_a0a0a0a0a0a0a0a0`) — both the timestamp and
// device-suffix lengths must match the HLC parser's invariants
// (`HLC_DEVICE_SUFFIX_HEX_LEN = 16`). Pre-fix this string ended in
// `_00000000` (8-char suffix), which the import-payload validator
// rejected on every preference / list / task row keyed by it the
// moment the import-roundtrip test happened to exercise the
// preference path. The validator never fired in CI because the
// preference-seeding harness path didn't exist (#3294 added it),
// but the malformed length was a latent bug all the same.
const SEED_VERSION = '0000000000000_0000_a0a0a0a0a0a0a0a0';

export function upsertPreference(db: Database.Database, key: string, value: unknown): void {
  const now = new Date().toISOString();
  db.prepare(`
    INSERT INTO preferences (key, value, version, updated_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
  `).run(key, JSON.stringify(value), SEED_VERSION, now);
}

export function resetBehaviorTables(db: Database.Database): void {
  // Wipe behavior tables but preserve the seeded `inbox` list so task
  // seeds keyed to the default `tasks.list_id = 'inbox'` FK remain
  // valid, AND preserve the harness-seeded `timezone` preference so
  // every per-scenario reset doesn't fall through to
  // `iana_time_zone::get_timezone()` (which on Linux reads
  // `/etc/localtime` BEFORE the `TZ` env var, ignoring the harness's
  // UTC pin — see #3294 for the date-flake symptoms).
  db.exec(`
    DELETE FROM tasks;
    DELETE FROM lists WHERE id != 'inbox';
    DELETE FROM preferences WHERE key != 'timezone';
    DELETE FROM memories;
    DELETE FROM ai_changelog;
    DELETE FROM focus_schedule;
    DELETE FROM current_focus;
    DELETE FROM sync_outbox;
  `);
}

export function insertListSeed(db: Database.Database, list: {
  id: string;
  name: string;
  icon?: string | null;
  color?: string | null;
}): void {
  const now = new Date().toISOString();
  db.prepare(`
    INSERT INTO lists (id, name, icon, color, version, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(list.id, list.name, list.icon ?? null, list.color ?? null, SEED_VERSION, now, now);
}

export function insertTaskSeed(db: Database.Database, task: {
  id: string;
  title: string;
  status?: 'open' | 'completed' | 'someday' | 'cancelled';
  list_id?: string;
  priority?: number | null;
  due_date?: string | null;
  estimated_minutes?: number | null;
  defer_count?: number;
  created_at?: string;
  updated_at?: string;
}): void {
  const now = new Date().toISOString();
  db.prepare(`
    INSERT INTO tasks (
      id, title, status, list_id, priority, due_date, estimated_minutes,
      defer_count, version, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    task.id,
    task.title,
    task.status ?? 'open',
    task.list_id ?? 'inbox',
    task.priority ?? null,
    task.due_date ?? null,
    task.estimated_minutes ?? null,
    task.defer_count ?? 0,
    SEED_VERSION,
    task.created_at ?? now,
    task.updated_at ?? now,
  );
}

/**
 * Resolve a tag name to its id, creating the tag row if it does not exist.
 */
function resolveOrCreateTagId(db: Database.Database, name: string, now: string): string {
  const lookupKey = name.toLowerCase();
  const existing = db.prepare('SELECT id FROM tags WHERE lookup_key = ?').get(lookupKey) as { id: string } | undefined;
  if (existing) {
    db.prepare('UPDATE tags SET updated_at = ? WHERE id = ?').run(now, existing.id);
    return existing.id;
  }
  const id = randomUUID();
  db.prepare(
    'INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(id, name, lookupKey, '0000000000000_0000_00000000', now, now);
  return id;
}

export function seedScaleDataset(db: Database.Database, total: number, listId = 'list-scale'): void {
  const now = new Date().toISOString();
  const today = daysFromTodayYmd(0);
  const tomorrow = daysFromTodayYmd(1);
  const inThreeDays = daysFromTodayYmd(3);
  const overdue = daysFromTodayYmd(-2);

  insertListSeed(db, {
    id: listId,
    name: 'Scale Test List',
    color: '#4F8EF7',
    icon: 'seed',
  });

  const insert = db.prepare(`
    INSERT INTO tasks (
      id, title, body, raw_input, ai_notes, status, list_id, priority,
      due_date, due_time, estimated_minutes,
      defer_count, version, created_at, updated_at, completed_at, last_deferred_at, planned_date
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const tagInsert = db.prepare('INSERT OR IGNORE INTO task_tags (task_id, tag_id) VALUES (?, ?)');

  // Pre-resolve tag ids for the fixed set of tags
  const tagNames = ['scale', 'query', 'guardrail', 'ops', 'benchmark'];
  const tagIdMap: Record<string, string> = {};
  for (const tagName of tagNames) {
    tagIdMap[tagName] = resolveOrCreateTagId(db, tagName, now);
  }

  const tx = db.transaction((count: number) => {
    for (let n = 1; n <= count; n += 1) {
      const status: 'open' | 'completed' = (
        n % 17 === 0 ? 'completed' : 'open'
      );
      const hasDeferHistory = n % 11 === 0;
      const dueDate = n % 6 === 0
        ? tomorrow
        : n % 6 === 1
          ? overdue
          : n % 6 === 2
            ? today
            : n % 6 === 3
              ? inThreeDays
              : null;
      const dueTime = dueDate != null && n % 8 === 0
        ? `${String((n % 9) + 9).padStart(2, '0')}:${String((n * 7) % 60).padStart(2, '0')}`
        : null;
      const tagList = n % 2 === 0
        ? ['scale', 'query', 'guardrail']
        : ['scale', 'ops', 'benchmark'];

      const taskId = `scale-it-${String(n).padStart(5, '0')}`;
      insert.run(
        taskId,
        `Scale task ${String(n).padStart(5, '0')}`,
        `Synthetic scale task #${n} for issue #92 regression checks.`,
        `seeded scale task #${n}`,
        n % 23 === 0 ? 'AI note: deferral risk.' : null,
        status,
        listId,
        (n % 3) + 1,
        dueDate,
        dueTime,
        ((n % 6) + 1) * 15,
        hasDeferHistory ? (n % 6) + 1 : 0,
        SEED_VERSION,
        now,
        now,
        status === 'completed' ? now : null,
        hasDeferHistory ? now : null,
        hasDeferHistory ? daysFromTodayYmd(((n % 14) + 1)) : null,
      );

      // Materialize tags to join table using pre-resolved tag ids
      for (const tag of tagList) {
        tagInsert.run(taskId, tagIdMap[tag]);
      }
    }
  });

  tx(total);
}
