# RFC-005: Export/Import System

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


*Status: IMPLEMENTED — MCP export/import + Settings snapshot export/import are shipped.*

---

## Problem

Users must be able to export all their data in a portable, human-readable format and import it back -- into the same instance, a new machine, or a future version of Lorvex. The format must handle schema evolution gracefully: old exports always importable, new fields never lost.

---

## Design Decisions

1. **JSONL, not raw SQLite.** A SQLite dump couples to internal schema. JSONL is portable, streamable, and inspectable.
2. **Manifest line first.** The first line contains metadata (schema version, timestamp, entity counts) so importers can validate before processing.
3. **Per-entity versioning.** Each line carries `_type` and `_version` so the importer knows exactly what schema produced it.
4. **In-memory string exchange, not file I/O.** The MCP tool returns/accepts raw JSONL strings. File handling is delegated to the caller (MCP client) or the Tauri app's Settings UI. This avoids filesystem permission issues and keeps the MCP surface stateless.

---

## Format Specification

### Structure

A JSONL string. Line 1 is the manifest. Lines 2+ are entities, one per line, in deterministic dependency order.

### Manifest Line

```json
{
  "_type": "manifest",
  "_version": 1,
  "schema_version": 1,
  "exported_at": "2026-02-28T14:30:00Z",
  "app": "lorvex",
  "counts": {
    "lists": 8,
    "tasks": 142,
    "current_focus": 5,
    "daily_reviews": 3,
    "preferences": 1,
    "memories": 12,
    "calendar_events": 0,
    "changelog": 1203
  }
}
```

Fields:
- `_type`: always `"manifest"` for the first line
- `_version`: manifest format version (currently `1`)
- `schema_version`: integer, incremented when entity schemas change in a breaking way
- `exported_at`: ISO 8601 timestamp
- `app`: application identifier (`"lorvex"`)
- `counts`: map of entity type to count (for validation)

### Entity Lines

Each line is a JSON object with two reserved fields plus all entity fields:

```json
{"_type": "list", "_version": 1, "id": "550e8400-e29b-41d4-a716-446655440000", "name": "Work", "color": "#4A90D9", "sort_order": 0, "is_default": 1, "created_at": "2026-01-15T09:00:00Z", "updated_at": "2026-02-28T14:00:00Z"}
{"_type": "task", "_version": 1, "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "title": "Write intro section", "list_id": "550e8400-e29b-41d4-a716-446655440000", "status": "active", "priority": 2, "due_date": "2026-03-01", "estimated_minutes": 45, "tags": "[\"writing\",\"paper\"]", "created_at": "2026-02-20T10:00:00Z", "updated_at": "2026-02-28T12:00:00Z"}
```

Reserved fields:
- `_type`: entity type name (matches table name: `task`, `list`, `current_focus`, `daily_review`, `preference`, `memory`, `calendar_event`, `changelog`)
- `_version`: integer schema version for this entity type

All other fields are the entity's columns, serialized as JSON values. JSON columns (like `tags`, `depends_on`) are stored as their string representation.

### Entity Order

Entities are written in dependency order:
1. `list` (no dependencies)
2. `task` (depends on `list` via `list_id`)
3. `current_focus`
4. `daily_review`
5. `preference`
6. `memory`
7. `calendar_event`
8. `changelog` (optional, controlled by `include_changelog`)

---

## MCP Tool Design

### `export_all_data`

```
Tool: export_all_data
Description: Export all Lorvex data as a JSONL string.
Input:
  - include_changelog (boolean, optional, default: true): Whether to include ai_changelog entries.
Output:
  - JSONL string containing manifest + all entity lines.
```

Implementation:
1. Query counts from each table for the manifest
2. Write manifest line
3. Stream entities table by table in dependency order
4. Return the complete JSONL string

### `import_data`

```
Tool: import_data
Description: Import JSONL data produced by export_all_data.
Input:
  - jsonl (string, required): The JSONL string to import.
  - conflict_mode (string, optional, default: "skip"): How to handle ID conflicts.
    "skip" = keep existing, "replace" = overwrite with imported.
  - include_changelog (boolean, optional, default: false): Whether to import changelog entries.
Output:
  - JSON summary with conflict_mode, per-entity import counts, skipped count, and total_lines.
```

Limits:
- Maximum JSONL size: 10 MB
- Maximum lines: 50,000

Implementation:
1. Read and validate manifest line
2. Check `schema_version` compatibility
3. Process entity lines within a transaction
4. For each entity: map `_type` to target table, check for ID conflict, apply conflict mode
5. Return structured import summary

---

## Tauri IPC Commands

```rust
#[tauri::command]
fn export_data_snapshot() -> Result<DataSnapshotExport, String> { }

#[tauri::command]
fn import_data_snapshot(snapshot_json: String, mode: String) -> Result<DataSnapshotImportResult, String> { }
```

The app-side commands operate on JSON snapshot text (copy/paste and file load/save handled in Settings UI). The UI surface is in `Settings > Data` and supports conflict modes (`skip`, `replace`) plus rollback snapshot creation.

---

## Migration Path and Compatibility

### Forward Compatibility (old export, new app)

- New columns added to the schema since the export was created get their default values on import
- The importer checks `schema_version` and applies transforms if needed (e.g., renaming a field that was changed between versions)
- Entity `_version` allows per-type migration logic

### Backward Compatibility (new export, old app)

- Fields the old app doesn't recognize are stored in `_extra` and preserved through the round-trip
- The old app ignores unknown `_type` values (logs a warning, skips the line)
- The manifest `counts` allows the old app to report "skipped N entities of unknown type"

### Guarantees

1. An export from any version of Lorvex can be imported into any newer version
2. Unknown fields are never silently discarded
3. Import is always transactional: it either fully succeeds or fully rolls back

---

## Deliberate Exclusions

- **File-path I/O in MCP tools** — file handling is the caller's responsibility (original RFC proposed optional `file_path` parameter; removed to keep MCP stateless)
- **Dry-run mode** — original RFC proposed `dry_run` parameter; not implemented (callers can preview by parsing the JSONL client-side)
- **Merge conflict strategy** — original RFC proposed "merge" (keep newer `updated_at`); not implemented (only `skip` and `replace` available)
- Incremental/differential export (full export only for v1)
- Binary/compressed format (JSONL is small enough for personal data volumes)
- Cloud backup integration (export is to local filesystem only)
- Selective export by entity type or date range (deferred to v2)
- Import from other task-manager apps -- separate RFC if needed
