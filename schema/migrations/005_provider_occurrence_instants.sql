-- EventKit's enumerated instants distinguish both readings of a repeated
-- clock. NULL keeps the legacy civil-time projection; a JSON array is the
-- authoritative fetched occurrence set (including an empty set).
-- Device-local provider data only: no sync payload change.
ALTER TABLE provider_calendar_events ADD COLUMN occurrence_instants TEXT
    CHECK (occurrence_instants IS NULL OR
           (json_valid(occurrence_instants) AND json_type(occurrence_instants) = 'array'));

-- Canonical occurrence arrays are sorted by source day / instant. Their first
-- UTC day bounds candidate selection even when a later refresh's representative
-- source start_date no longer covers earlier cached observations. Split this
-- indexed leg from legacy civil recurrence queries instead of an unbounded OR.
CREATE INDEX idx_provider_events_observed_start
    ON provider_calendar_events(date(json_extract(occurrence_instants, '$[0].start'), 'unixepoch'))
    WHERE recurrence IS NOT NULL AND occurrence_instants IS NOT NULL;
