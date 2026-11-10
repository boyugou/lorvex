-- A task can be handed to the person's assistant. While the row exists the
-- task is delegated: `state` says whether the assistant still holds it
-- ('assistant') or has handed it back with what it did ('returned'); deleting
-- the row takes the task back. The relation is a synced composite edge keyed
-- by (task, assignee), like `habit_completions`: the left half is an aggregate
-- id and the right half a plain name that never merges.

-- 1. The delegation edge. `assignee` names who the task was handed to. Every
--    first-party writer uses 'assistant'; the column is a lowercase identifier
--    rather than that one word, so a named agent can follow without rebuilding
--    the table. `request` is what the person asked for, in their words. A task
--    that is deleted or merged away drops its delegations through the cascade.
CREATE TABLE task_delegations (
    task_id    TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    assignee   TEXT NOT NULL CHECK (
        length(assignee) BETWEEN 1 AND 32
        AND assignee NOT GLOB '*[^a-z0-9_]*'
    ),
    state      TEXT NOT NULL CHECK (state IN ('assistant', 'returned')),
    request    TEXT CHECK (request IS NULL OR length(request) BETWEEN 1 AND 2000),
    version    TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (task_id, assignee)
) STRICT;

-- "What is waiting for the assistant" and "what did it hand back" read by
-- state across all tasks.
CREATE INDEX idx_task_delegations_state ON task_delegations(assignee, state);

-- 2. Taking a task back leaves a tombstone, so the tombstone table accepts the
--    new entity type. SQLite cannot alter a CHECK constraint, so the table is
--    rebuilt with the extended list; no other object references it.
CREATE TABLE sync_tombstones_rebuilt (
    entity_type TEXT NOT NULL CHECK (
        entity_type IN (
            'task', 'list', 'habit', 'tag', 'calendar_event', 'preference',
            'memory', 'daily_review', 'daily_briefing',
            'task_reminder', 'task_checklist_item', 'habit_reminder_policy',
            'task_tag', 'task_dependency', 'task_calendar_event_link',
            'habit_completion', 'habit_skip', 'task_delegation'
        )
    ),
    entity_id   TEXT NOT NULL,
    version     TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    deleted_at  TEXT NOT NULL,
    PRIMARY KEY (entity_type, entity_id)
) STRICT;

INSERT INTO sync_tombstones_rebuilt (entity_type, entity_id, version, deleted_at)
SELECT entity_type, entity_id, version, deleted_at FROM sync_tombstones;

DROP TABLE sync_tombstones;
ALTER TABLE sync_tombstones_rebuilt RENAME TO sync_tombstones;

CREATE INDEX idx_sync_tombstones_version
    ON sync_tombstones(version);
