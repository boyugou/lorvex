-- Seed data for Lorvex development/testing.
-- Run with: sqlite3 ~/Library/Application\ Support/Lorvex/db.sqlite < scripts/fixtures/seed.sql

-- Lists
INSERT OR IGNORE INTO lists (id, name, color, icon, description, created_at, updated_at) VALUES
  ('list-work',     'Work',      '#4F8EF7', '💼', 'Professional tasks and projects',   datetime('now'), datetime('now')),
  ('list-personal', 'Personal',  '#F7854F', '🏠', 'Personal errands and goals',        datetime('now'), datetime('now')),
  ('list-learning', 'Learning',  '#8B5CF6', '📚', 'Books, courses, and self-study',    datetime('now'), datetime('now')),
  ('list-health',   'Health',    '#10B981', '🏃', 'Fitness, health, and wellness',     datetime('now'), datetime('now'));

-- Work tasks
INSERT OR IGNORE INTO tasks (id, title, body, status, list_id, priority, due_date, estimated_minutes, defer_count, created_at, updated_at) VALUES
  ('t-001', 'Review Q1 OKR progress',         'Check all team OKRs and prepare summary for leadership sync.', 'open', 'list-work', 1, date('now'), 45, 0, datetime('now', '-2 days'), datetime('now')),
  ('t-002', 'Finalize API spec for v2',        NULL, 'open', 'list-work', 2, date('now', '+1 day'), 90, 0, datetime('now', '-5 days'), datetime('now')),
  ('t-003', 'Code review: auth refactor PR',   'PR #342 — new JWT rotation logic.', 'open', 'list-work', 2, date('now', '+2 days'), 30, 0, datetime('now', '-1 day'), datetime('now')),
  ('t-004', 'Update onboarding docs',          NULL, 'open', 'list-work', 3, date('now', '+7 days'), 60, 1, datetime('now', '-10 days'), datetime('now')),
  ('t-005', 'Ship monitoring dashboard',       'Grafana dashboards for new microservice.', 'completed', 'list-work', 2, date('now', '-1 day'), 120, 0, datetime('now', '-7 days'), datetime('now', '-1 day'));
UPDATE tasks SET completed_at = datetime('now', '-1 day') WHERE id = 't-005';

-- Personal tasks
INSERT OR IGNORE INTO tasks (id, title, body, status, list_id, priority, due_date, estimated_minutes, defer_count, created_at, updated_at) VALUES
  ('t-006', 'Call dentist for cleaning',       NULL, 'open', 'list-personal', 3, date('now', '+3 days'), 10, 2, datetime('now', '-14 days'), datetime('now')),
  ('t-007', 'Fix kitchen faucet leak',         'Slow drip from the hot water side.', 'open', 'list-personal', 2, date('now', '+5 days'), 60, 0, datetime('now', '-3 days'), datetime('now')),
  ('t-008', 'Plan weekend hiking trip',        NULL, 'open', 'list-personal', 4, date('now', '+4 days'), 30, 0, datetime('now', '-1 day'), datetime('now'));

-- Learning tasks
INSERT OR IGNORE INTO tasks (id, title, body, status, list_id, priority, due_date, estimated_minutes, defer_count, created_at, updated_at) VALUES
  ('t-009', 'Read "Designing Data-Intensive Applications" Ch. 7', 'Transactions chapter.', 'open', 'list-learning', 3, NULL, 90, 0, datetime('now', '-4 days'), datetime('now')),
  ('t-010', 'Complete Rust ownership exercises', NULL, 'open', 'list-learning', 3, NULL, 45, 0, datetime('now', '-2 days'), datetime('now'));

-- Health tasks
INSERT OR IGNORE INTO tasks (id, title, body, status, list_id, due_date, estimated_minutes, defer_count, created_at, updated_at) VALUES
  ('t-011', 'Morning run — 5K',               NULL, 'completed', 'list-health', date('now'), 30, 0, datetime('now'), datetime('now')),
  ('t-012', 'Schedule annual physical',        NULL, 'open', 'list-health', date('now', '+14 days'), 10, 0, datetime('now', '-3 days'), datetime('now'));
UPDATE tasks SET completed_at = datetime('now', '-2 hours') WHERE id = 't-011';

-- Open tasks (previously inbox)
INSERT OR IGNORE INTO tasks (id, title, raw_input, ai_notes, status, defer_count, created_at, updated_at) VALUES
  ('t-013', 'Buy anniversary gift',           'Oh I need to get Sarah something nice for our anniversary', 'User mentions anniversary — likely personal. No specific date mentioned; may need clarification.', 'open', 0, datetime('now', '-1 hour'), datetime('now')),
  ('t-014', 'Research standing desk options',  'maybe I should get a standing desk',   'Casual mention — user exploring the idea. Could be personal or work-related.', 'open', 0, datetime('now', '-30 minutes'), datetime('now')),
  ('t-015', 'Write blog post about MCP',      'I should write about my MCP server experience', 'User wants to write a technical blog post about Model Context Protocol. Could be work-related content marketing.', 'open', 0, datetime('now', '-10 minutes'), datetime('now'));

-- Someday tasks
INSERT OR IGNORE INTO tasks (id, title, body, status, list_id, defer_count, created_at, updated_at) VALUES
  ('t-016', 'Learn piano',                    'Always wanted to pick this up. Maybe start with YouTube tutorials.', 'someday', NULL, 0, datetime('now', '-30 days'), datetime('now')),
  ('t-017', 'Build a personal website',        NULL, 'someday', NULL, 0, datetime('now', '-20 days'), datetime('now')),
  ('t-018', 'Watch The Shawshank Redemption',  'Classic movie, keep hearing about it.', 'someday', NULL, 0, datetime('now', '-15 days'), datetime('now'));

-- Previously deferred task (now open with planned_date)
INSERT OR IGNORE INTO tasks (id, title, status, list_id, priority, due_date, planned_date, defer_count, last_deferred_at, created_at, updated_at) VALUES
  ('t-019', 'Tax document review',            'open', 'list-personal', 2, date('now', '+30 days'), date('now', '+7 days'), 3, datetime('now', '-2 days'), datetime('now', '-45 days'), datetime('now'));

-- Tags vocabulary (with UUIDs)
INSERT OR IGNORE INTO tags (id, name) VALUES
  ('tag-seed-okrs',              'okrs'),
  ('tag-seed-leadership',        'leadership'),
  ('tag-seed-api',               'api'),
  ('tag-seed-design',            'design'),
  ('tag-seed-code-review',       'code-review'),
  ('tag-seed-docs',              'docs'),
  ('tag-seed-infra',             'infra'),
  ('tag-seed-monitoring',        'monitoring'),
  ('tag-seed-health',            'health'),
  ('tag-seed-calls',             'calls'),
  ('tag-seed-home',              'home'),
  ('tag-seed-outdoors',          'outdoors'),
  ('tag-seed-planning',          'planning'),
  ('tag-seed-reading',           'reading'),
  ('tag-seed-distributed-systems','distributed-systems'),
  ('tag-seed-rust',              'rust'),
  ('tag-seed-coding',            'coding'),
  ('tag-seed-exercise',          'exercise'),
  ('tag-seed-appointments',      'appointments'),
  ('tag-seed-music',             'music'),
  ('tag-seed-hobby',             'hobby'),
  ('tag-seed-portfolio',         'portfolio'),
  ('tag-seed-movies',            'movies');

-- Task tags (join table — references tag_id)
INSERT OR IGNORE INTO task_tags (task_id, tag_id) VALUES
  ('t-001', 'tag-seed-okrs'), ('t-001', 'tag-seed-leadership'),
  ('t-002', 'tag-seed-api'), ('t-002', 'tag-seed-design'),
  ('t-003', 'tag-seed-code-review'),
  ('t-004', 'tag-seed-docs'),
  ('t-005', 'tag-seed-infra'), ('t-005', 'tag-seed-monitoring'),
  ('t-006', 'tag-seed-health'), ('t-006', 'tag-seed-calls'),
  ('t-007', 'tag-seed-home'),
  ('t-008', 'tag-seed-outdoors'), ('t-008', 'tag-seed-planning'),
  ('t-009', 'tag-seed-reading'), ('t-009', 'tag-seed-distributed-systems'),
  ('t-010', 'tag-seed-rust'), ('t-010', 'tag-seed-coding'),
  ('t-011', 'tag-seed-exercise'),
  ('t-012', 'tag-seed-appointments'),
  ('t-016', 'tag-seed-music'), ('t-016', 'tag-seed-hobby'),
  ('t-017', 'tag-seed-coding'), ('t-017', 'tag-seed-portfolio'),
  ('t-018', 'tag-seed-movies');

-- AI changelog entries
INSERT OR IGNORE INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, mcp_tool) VALUES
  ('cl-001', datetime('now', '-2 hours'), 'create',  'task',  't-013', 'Captured task from conversation: "Buy anniversary gift"',                 'create_task'),
  ('cl-002', datetime('now', '-1 hour'),  'create',  'task',  't-014', 'Captured task from conversation: "Research standing desk options"',        'create_task'),
  ('cl-003', datetime('now', '-45 minutes'), 'create', 'task', 't-015', 'Captured task from conversation: "Write blog post about MCP"',           'create_task'),
  ('cl-004', datetime('now', '-30 minutes'), 'triage', 'task', 't-001', 'Escalated priority for "Review Q1 OKR progress" — due today',            'update_task'),
  ('cl-005', datetime('now', '-15 minutes'), 'plan',   'current_focus', NULL, 'Set daily focus: Q1 OKR review, API spec, auth code review',         'set_current_focus');

-- Daily plan for today
INSERT OR REPLACE INTO current_focus (date, briefing, created_at, updated_at) VALUES
  (date('now'), 'Good morning! Three key items today: the Q1 OKR review is due by EOD and is your highest priority. The API spec for v2 needs finishing tomorrow — get ahead on it if time allows. The auth refactor PR has been waiting for review. Suggested order: OKRs first (freshest mind), then API spec (deep work), then code review (lighter context-switch).', datetime('now'), datetime('now'));
INSERT OR IGNORE INTO current_focus_items (date, position, task_id) VALUES
  (date('now'), 0, 't-001'),
  (date('now'), 1, 't-002'),
  (date('now'), 2, 't-003');
