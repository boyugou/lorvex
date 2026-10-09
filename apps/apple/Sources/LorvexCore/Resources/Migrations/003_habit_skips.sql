-- A habit can be excused for one day. A skipped day is neither completed nor
-- missed: the habit is not required on that date, so the streak carries over
-- it and the day leaves the completion rate. The relation is a synced
-- composite edge keyed by (habit, local calendar date), like `habit_completions`;
-- deleting the row un-skips the day.

-- 1. The per-day skip relation. A habit that is deleted or merged away drops
--    its skips through the cascade; the winner of a merge keeps its own rows.
CREATE TABLE habit_skips (
    habit_id     TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    skipped_date TEXT NOT NULL,
    version      TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    PRIMARY KEY (habit_id, skipped_date)
) STRICT;

-- The day-scoped reads ("which habits are excused on this date") filter on the
-- date alone.
CREATE INDEX idx_habit_skips_date ON habit_skips(skipped_date DESC);

-- 2. Deleting a skip leaves a tombstone, so the tombstone table accepts the new
--    entity type. SQLite cannot alter a CHECK constraint, so the table is
--    rebuilt with the extended list; no other object references it.
CREATE TABLE sync_tombstones_rebuilt (
    entity_type TEXT NOT NULL CHECK (
        entity_type IN (
            'task', 'list', 'habit', 'tag', 'calendar_event', 'preference',
            'memory', 'daily_review', 'daily_briefing',
            'task_reminder', 'task_checklist_item', 'habit_reminder_policy',
            'task_tag', 'task_dependency', 'task_calendar_event_link',
            'habit_completion', 'habit_skip'
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
