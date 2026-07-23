import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import test from 'node:test';

// #4345 step e — the canonical calendar_event create/update field
// sets must be in lockstep across the three consumer surfaces that
// build a `lorvex_workflow::calendar_event::CalendarEvent{Create,Update}Input`:
//
//   - MCP server: `mcp-server/src/contract/calendar/events.rs`
//     (`CreateCalendarEventArgs` / flattened `CalendarEventUpdateWire`)
//   - CLI:        `lorvex-cli/src/commands/mutate/calendar/effects/types.rs`
//     (`CalendarEventCreateFields` / `CalendarEventUpdateFields`)
//   - Tauri:      `app/src-tauri/src/commands/calendar/events/create/mod.rs`
//     and `lorvex-sync-payload/src/calendar_event_wire.rs`
//     (`CreateCalendarEventArgs` / `CalendarEventUpdateWire`)
//
// A field added to the workflow input without a matching surface
// field silently drops on the surface's path the next time the
// mutation routes through workflow; a field added to one surface
// without a workflow counterpart hits an assistant-visible "unknown
// field" or — worse — gets silently ignored. Both classes show up
// here as a name set mismatch.
//
// Each surface gets an explicit allow-list of boundary-only fields
// (e.g. MCP-only `idempotency_key`, `dry_run`, `include_diff`) that
// stay out of the parity check because they don't have workflow
// counterparts by design.

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..', '..', '..');

const WORKFLOW_PATH = resolve(REPO_ROOT, 'lorvex-workflow/src/calendar_event/mod.rs');
const MCP_PATH = resolve(REPO_ROOT, 'mcp-server/src/contract/calendar/events.rs');
const CALENDAR_EVENT_WIRE_PATH = resolve(
  REPO_ROOT,
  'lorvex-sync-payload/src/calendar_event_wire.rs',
);
const CLI_PATH = resolve(
  REPO_ROOT,
  'lorvex-cli/src/commands/mutate/calendar/effects/types.rs',
);
const TAURI_CREATE_PATH = resolve(
  REPO_ROOT,
  'app/src-tauri/src/commands/calendar/events/create/mod.rs',
);
const TAURI_UPDATE_PATH = CALENDAR_EVENT_WIRE_PATH;

/**
 * Parse a Rust source file and extract the public/crate-public field
 * names declared inside the first `struct StructName ... { ... }`
 * block. Tolerates lifetime/generic parameters on the struct head
 * (e.g. `struct Foo<'a> { ... }`).
 *
 * Skips `//` comments and `#[...]` attribute lines so the field
 * regex sees only `name: Type,` lines.
 */
function extractStructFields(filePath, structName) {
  const source = readFileSync(filePath, 'utf8');
  const structRe = new RegExp(
    `struct\\s+${structName}\\b[^\\{]*\\{([\\s\\S]*?)\\n\\}`,
    'm',
  );
  const match = source.match(structRe);
  assert.ok(match, `${filePath} must declare 'struct ${structName} { ... }'`);
  const body = match[1];
  const fields = [];
  for (const rawLine of body.split('\n')) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('//') || line.startsWith('#[')) {
      continue;
    }
    // pub[(crate)] name: Type,    or    name: Type,    (private fields)
    const fieldMatch = line.match(
      /^(?:pub(?:\([a-z()]+\))?\s+)?([a-z_][a-z_0-9]*)\s*:/,
    );
    if (fieldMatch) {
      fields.push(fieldMatch[1]);
    }
  }
  return fields;
}

function setDiff(left, right) {
  return [...left].filter((value) => !right.has(value)).sort();
}

// Fields the workflow defines but a given surface deliberately omits.
// The create surfaces still cannot author attendees on every path,
// so they route creation without that optional sub-table payload.
const SURFACE_WORKFLOW_OMISSIONS = {
  mcpCreate: new Set(),
  mcpUpdate: new Set(),
  cliCreate: new Set(['attendees']),
  cliUpdate: new Set(),
  tauriCreate: new Set(['attendees']),
  tauriUpdate: new Set(),
};

// Fields a surface accepts that have no workflow counterpart by
// design. MCP carries `idempotency_key` / `dry_run` / `include_diff`
// for RPC retry de-duplication, preview, and diff-mode response
// shaping; none of those make sense on the workflow input.
const SURFACE_BOUNDARY_ONLY_FIELDS = {
  mcpCreate: new Set(['idempotency_key', 'dry_run']),
  mcpUpdate: new Set(['idempotency_key', 'dry_run', 'include_diff']),
  cliCreate: new Set(),
  cliUpdate: new Set(),
  tauriCreate: new Set(),
  tauriUpdate: new Set(),
};

function assertParity(label, workflowFields, surfaceFields, surfaceKey) {
  const omissions = SURFACE_WORKFLOW_OMISSIONS[surfaceKey];
  const boundaryOnly = SURFACE_BOUNDARY_ONLY_FIELDS[surfaceKey];
  const workflowSet = new Set(workflowFields.filter((f) => !omissions.has(f)));
  const surfaceSet = new Set(surfaceFields.filter((f) => !boundaryOnly.has(f)));

  const missingOnSurface = setDiff(workflowSet, surfaceSet);
  const extraOnSurface = setDiff(surfaceSet, workflowSet);

  assert.deepEqual(
    missingOnSurface,
    [],
    `${label}: fields present in workflow input but missing from surface: ${missingOnSurface.join(', ')}.\n` +
      `Either add the field to the surface struct, or list it in SURFACE_WORKFLOW_OMISSIONS[${JSON.stringify(surfaceKey)}] ` +
      `(scripts/tests/contracts/repo_governance/calendar_event_field_parity.test.mjs) with a comment explaining the gap.`,
  );
  assert.deepEqual(
    extraOnSurface,
    [],
    `${label}: fields present on surface but missing from workflow input: ${extraOnSurface.join(', ')}.\n` +
      `Either mirror the additions into lorvex-workflow/src/calendar_event/mod.rs::CalendarEvent{Create,Update}Input, ` +
      `or list them in SURFACE_BOUNDARY_ONLY_FIELDS[${JSON.stringify(surfaceKey)}] with a comment explaining why they don't cross the workflow boundary.`,
  );
}

test('calendar_event create/update field sets agree across MCP, CLI, Tauri, and workflow', () => {
  const workflowCreate = extractStructFields(WORKFLOW_PATH, 'CalendarEventCreateInput');
  const workflowUpdate = extractStructFields(WORKFLOW_PATH, 'CalendarEventUpdateInput');

  // Defensive: a regex regression that drops everything would
  // silently make the parity assertions pass against two empty sets.
  // Workflow inputs each carry ~15 fields.
  assert.ok(workflowCreate.length >= 12, `workflow CalendarEventCreateInput parsed only ${workflowCreate.length} fields`);
  assert.ok(workflowUpdate.length >= 12, `workflow CalendarEventUpdateInput parsed only ${workflowUpdate.length} fields`);

  // The `id` field on the update input is the row selector, not a
  // patch field — it's required on every surface that selects a row
  // (MCP, Tauri) but conceptually distinct from the patch payload.
  // Strip it for parity to keep the comparison about patchable
  // field surface alone.
  const stripId = (fields) => fields.filter((f) => f !== 'id');
  const workflowUpdatePatch = stripId(workflowUpdate);

  const mcpCreate = extractStructFields(MCP_PATH, 'CreateCalendarEventArgs');
  const updateWire = extractStructFields(CALENDAR_EVENT_WIRE_PATH, 'CalendarEventUpdateWire');
  const mcpUpdateWrapper = extractStructFields(MCP_PATH, 'UpdateCalendarEventArgs');
  for (const field of ['wire', 'idempotency_key', 'dry_run', 'include_diff']) {
    assert.ok(
      mcpUpdateWrapper.includes(field),
      `MCP update wrapper must expose '${field}' while flattening CalendarEventUpdateWire`,
    );
  }
  const mcpUpdate = stripId([...updateWire, 'idempotency_key', 'dry_run', 'include_diff']);

  const cliCreate = extractStructFields(CLI_PATH, 'CalendarEventCreateFields');
  const cliUpdate = extractStructFields(CLI_PATH, 'CalendarEventUpdateFields');

  const tauriCreate = extractStructFields(TAURI_CREATE_PATH, 'CreateCalendarEventArgs');
  const tauriUpdate = stripId(updateWire);

  assertParity('MCP create', workflowCreate, mcpCreate, 'mcpCreate');
  assertParity('MCP update', workflowUpdatePatch, mcpUpdate, 'mcpUpdate');
  assertParity('CLI create', workflowCreate, cliCreate, 'cliCreate');
  assertParity('CLI update', workflowUpdatePatch, cliUpdate, 'cliUpdate');
  assertParity('Tauri create', workflowCreate, tauriCreate, 'tauriCreate');
  assertParity('Tauri update', workflowUpdatePatch, tauriUpdate, 'tauriUpdate');
});
