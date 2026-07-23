-- Scale seed for large-volume resilience checks (1k / 10k tasks).
--
-- Usage:
--   DB="$HOME/Library/Application Support/Lorvex/db.sqlite"
--   sqlite3 "$DB" ".parameter init" ".parameter set @max_n 1000"  ".read scripts/fixtures/seed_scale.sql"
--   sqlite3 "$DB" ".parameter init" ".parameter set @max_n 10000" ".read scripts/fixtures/seed_scale.sql"
--
-- Notes:
-- - This script is idempotent for the scale dataset (removes prior scale-* rows first).
-- - @max_n defaults to 10000 if not provided.
-- - Designed to avoid deep recursive CTE limits.

PRAGMA foreign_keys = ON;

INSERT OR IGNORE INTO lists (id, name, color, icon, description, created_at, updated_at)
VALUES ('list-scale', 'Scale Test', '#4F8EF7', '⚙️', 'Synthetic high-volume dataset for resilience checks', datetime('now'), datetime('now'));

DELETE FROM task_tags WHERE task_id LIKE 'scale-%';
DELETE FROM tasks WHERE id LIKE 'scale-%';

WITH RECURSIVE
  a(i) AS (
    SELECT 0
    UNION ALL
    SELECT i + 1 FROM a WHERE i < 99
  ),
  b(j) AS (
    SELECT 0
    UNION ALL
    SELECT j + 1 FROM b WHERE j < 99
  ),
  seq(n) AS (
    SELECT (a.i * 100 + b.j + 1) AS n
    FROM a CROSS JOIN b
  )
INSERT INTO tasks (
  id,
  title,
  body,
  raw_input,
  ai_notes,
  status,
  list_id,
  priority,
  due_date,
  due_time,
  estimated_minutes,
  created_at,
  updated_at,
  completed_at,
  last_deferred_at,
  defer_count,
  planned_date
)
SELECT
  printf('scale-%05d', n) AS id,
  printf('Scale task %05d', n) AS title,
  printf('Synthetic task #%05d for load and context-budget validation.', n) AS body,
  printf('auto-generated scale task %05d', n) AS raw_input,
  CASE
    WHEN n % 23 = 0 THEN 'AI note: deferral risk due to repeated postponement.'
    WHEN n % 17 = 0 THEN 'AI note: candidate for batching.'
    ELSE NULL
  END AS ai_notes,
  CASE
    WHEN n % 17 = 0 THEN 'completed'
    WHEN n % 11 = 0 THEN 'open'
    WHEN n % 13 = 0 THEN 'open'
    ELSE 'open'
  END AS status,
  'list-scale' AS list_id,
  (n % 3) + 1 AS priority,
  CASE
    WHEN n % 6 = 0 THEN date('now', printf('+%d day', n % 14))
    WHEN n % 6 = 1 THEN date('now', printf('-%d day', n % 7))
    ELSE NULL
  END AS due_date,
  CASE
    WHEN n % 8 = 0 THEN printf('%02d:%02d', (n % 9) + 9, (n * 7) % 60)
    ELSE NULL
  END AS due_time,
  ((n % 6) + 1) * 15 AS estimated_minutes,
  datetime('now', printf('-%d minute', n % 20000)) AS created_at,
  datetime('now', printf('-%d minute', n % 18000)) AS updated_at,
  CASE WHEN n % 17 = 0 THEN datetime('now', printf('-%d hour', n % 240)) ELSE NULL END AS completed_at,
  CASE WHEN n % 11 = 0 THEN datetime('now', printf('-%d hour', n % 168)) ELSE NULL END AS last_deferred_at,
  CASE WHEN n % 11 = 0 THEN (n % 6) + 1 ELSE 0 END AS defer_count,
  CASE WHEN n % 11 = 0 THEN date('now', printf('+%d day', (n % 14) + 1)) ELSE NULL END AS planned_date
FROM seq
WHERE n <= COALESCE(@max_n, 10000);

-- Materialize tags to the task_tags join table (via tag_id)
-- Ensure vocabulary entries exist with stable UUIDs
INSERT OR IGNORE INTO tags (id, name) VALUES
  ('tag-scale-scale',    'scale'),
  ('tag-scale-backend',  'backend'),
  ('tag-scale-query',    'query'),
  ('tag-scale-frontend', 'frontend'),
  ('tag-scale-ux',       'ux'),
  ('tag-scale-sync',     'sync'),
  ('tag-scale-provider', 'provider'),
  ('tag-scale-planning', 'planning'),
  ('tag-scale-roadmap',  'roadmap'),
  ('tag-scale-ops',      'ops'),
  ('tag-scale-quality',  'quality');

-- Insert tag assignments based on the same n % 5 pattern
WITH RECURSIVE
  a(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM a WHERE i < 99),
  b(j) AS (SELECT 0 UNION ALL SELECT j + 1 FROM b WHERE j < 99),
  seq(n) AS (SELECT (a.i * 100 + b.j + 1) AS n FROM a CROSS JOIN b)
INSERT OR IGNORE INTO task_tags (task_id, tag_id)
SELECT printf('scale-%05d', n), 'tag-scale-scale' FROM seq WHERE n <= COALESCE(@max_n, 10000)
UNION ALL
SELECT printf('scale-%05d', n), CASE
  WHEN n % 5 = 0 THEN 'tag-scale-backend'
  WHEN n % 5 = 1 THEN 'tag-scale-frontend'
  WHEN n % 5 = 2 THEN 'tag-scale-sync'
  WHEN n % 5 = 3 THEN 'tag-scale-planning'
  ELSE 'tag-scale-ops'
END FROM seq WHERE n <= COALESCE(@max_n, 10000)
UNION ALL
SELECT printf('scale-%05d', n), CASE
  WHEN n % 5 = 0 THEN 'tag-scale-query'
  WHEN n % 5 = 1 THEN 'tag-scale-ux'
  WHEN n % 5 = 2 THEN 'tag-scale-provider'
  WHEN n % 5 = 3 THEN 'tag-scale-roadmap'
  ELSE 'tag-scale-quality'
END FROM seq WHERE n <= COALESCE(@max_n, 10000);
