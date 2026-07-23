import Database from 'better-sqlite3';

const SEED_VERSION = '0000000000000_0000_a0a0a0a0a0a0a0a0';

function daysFromTodayYmd(offsetDays = 0): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offsetDays);
  return date.toISOString().slice(0, 10);
}

export function seedScaleDataset(dbPath: string, total: number, listId = 'list-scale'): void {
  const db = new Database(dbPath, { fileMustExist: true });
  try {
    const now = new Date().toISOString();
    const today = daysFromTodayYmd(0);
    const tomorrow = daysFromTodayYmd(1);
    const inThreeDays = daysFromTodayYmd(3);
    const overdue = daysFromTodayYmd(-2);

    db.exec(`
      DELETE FROM task_tags;
      DELETE FROM tasks;
      DELETE FROM tags;
      DELETE FROM lists;
      DELETE FROM preferences;
      DELETE FROM memories;
      DELETE FROM ai_changelog;
      DELETE FROM focus_schedule;
      DELETE FROM current_focus;
      DELETE FROM sync_outbox;
    `);

    db.prepare(`
      INSERT INTO lists (id, name, color, icon, description, version, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(listId, 'Scale Test List', '#4F8EF7', 'seed', 'Scale benchmark dataset', SEED_VERSION, now, now);

    const insert = db.prepare(`
      INSERT INTO tasks (
        id, title, body, raw_input, ai_notes, status, list_id, priority, due_date, due_time, estimated_minutes,
        defer_count, version, created_at, updated_at, completed_at, last_deferred_at, planned_date
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const tagInsert = db.prepare(`
      INSERT OR IGNORE INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    const taskTagInsert = db.prepare(`
      INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at)
      VALUES (?, ?, ?, ?)
    `);
    const tagIdByName: Record<string, string> = {};
    for (const tagName of ['scale', 'query', 'guardrail', 'ops', 'benchmark']) {
      const tagId = `scale-tag-${tagName}`;
      tagIdByName[tagName] = tagId;
      tagInsert.run(tagId, tagName, tagName, SEED_VERSION, now, now);
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
        const tagNames = n % 2 === 0
          ? ['scale', 'query', 'guardrail']
          : ['scale', 'ops', 'benchmark'];
        const taskId = `scale-bench-${String(n).padStart(5, '0')}`;
        insert.run(
          taskId,
          `Scale task ${String(n).padStart(5, '0')}`,
          `Synthetic scale benchmark task #${n}`,
          `scale benchmark seed #${n}`,
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
        for (const tagName of tagNames) {
          taskTagInsert.run(taskId, tagIdByName[tagName], SEED_VERSION, now);
        }
      }
    });

    tx(total);
  } finally {
    db.close();
  }
}
