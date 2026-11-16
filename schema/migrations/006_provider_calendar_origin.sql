-- Origin belongs to the device-local provider mirror, never to CloudKit.
-- Only full-detail observations may carry it; older rows have unknown origin.
ALTER TABLE provider_calendar_events ADD COLUMN origin_json TEXT
    CHECK (origin_json IS NULL OR
           (json_valid(origin_json) AND json_type(origin_json) = 'object'));

-- Re-fetch disposable EventKit observations with calendar-qualified identities.
-- Keep task links: the ingest adapter reassociates an old UID only when exactly
-- one source copy is known. Owned events and all synchronization data survive.
DELETE FROM provider_calendar_events WHERE provider_kind = 'eventkit';
