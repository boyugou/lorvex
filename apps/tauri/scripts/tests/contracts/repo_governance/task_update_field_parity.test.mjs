import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import test from 'node:test';

// #4343 — the canonical task_update field set must be identical
// between MCP's wire contract (`UpdateTaskArgs`) and the
// cross-surface workflow input (`TaskUpdateInput`). Both live in
// Rust struct definitions; this test parses each file with a small
// regex pass over the `#[serde(...)]`-decorated struct and asserts
// the resulting field name sets agree.
//
// Why a separate test instead of a shared codegen source: the two
// structs differ on inner types (MCP keeps typed enums for `status`
// + structured `RecurrenceRuleArgs`; the workflow accepts the lowered
// JSON shapes both surfaces lower to) but their wire-level field
// names must stay in lockstep. A field added to MCP without a
// matching workflow field silently drops on the Tauri / CLI path
// the next time the update routes through workflow; this gate
// fails CI before that ships.

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..', '..', '..');

const MCP_ARGS_PATH = resolve(
  REPO_ROOT,
  'mcp-server/src/contract/task/single_update.rs',
);
const WORKFLOW_INPUT_PATH = resolve(
  REPO_ROOT,
  'lorvex-workflow/src/task_update/input.rs',
);
const TAURI_COMMAND_PATH = resolve(
  REPO_ROOT,
  'app/src-tauri/src/commands/tasks/updates/command.rs',
);

/**
 * Parse a Rust source file and extract the public/crate-public field
 * names declared inside the first `struct StructName { ... }` block.
 *
 * Accepts both `pub(crate) name: T,` and `pub name: T,` and skips
 * `#[...]` attributes that decorate the field. The parser is
 * intentionally minimal — both target structs are flat field lists
 * with no nested types or generic constraints, so a regex pass is
 * sufficient and avoids the cost of a Rust-grade parser.
 */
function extractStructFields(filePath, structName) {
  const source = readFileSync(filePath, 'utf8');
  const structRe = new RegExp(
    `struct\\s+${structName}\\s*\\{([\\s\\S]*?)\\n\\}`,
    'm',
  );
  const match = source.match(structRe);
  assert.ok(
    match,
    `${filePath} must declare 'struct ${structName} { ... }'`,
  );
  const body = match[1];
  // Drop comments + attributes; keep only `name: Type,` lines.
  const fields = [];
  for (const rawLine of body.split('\n')) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('//') || line.startsWith('#[')) {
      continue;
    }
    // pub[(crate)] name: Type,
    const fieldMatch = line.match(/^pub(?:\([a-z()]+\))?\s+([a-z_][a-z_0-9]*)\s*:/);
    if (fieldMatch) {
      fields.push(fieldMatch[1]);
    }
  }
  return fields;
}

const MCP_BOUNDARY_ONLY_FIELDS = new Set([
  // MCP-only retry de-duplication token. Tauri and CLI don't speak
  // RPC retries, so the workflow input doesn't need to model it.
  'idempotency_key',
]);

test('UpdateTaskArgs and TaskUpdateInput accept identical field sets', () => {
  const mcpFields = extractStructFields(MCP_ARGS_PATH, 'UpdateTaskArgs');
  const workflowFields = extractStructFields(WORKFLOW_INPUT_PATH, 'TaskUpdateInput');

  const mcpSet = new Set(mcpFields.filter((f) => !MCP_BOUNDARY_ONLY_FIELDS.has(f)));
  const workflowSet = new Set(workflowFields);

  const onlyInMcp = [...mcpSet].filter((f) => !workflowSet.has(f)).sort();
  const onlyInWorkflow = [...workflowSet].filter((f) => !mcpSet.has(f)).sort();

  assert.deepEqual(
    onlyInMcp,
    [],
    `Fields present in MCP UpdateTaskArgs but missing from workflow TaskUpdateInput: ${onlyInMcp.join(', ')}.\n` +
      `Add the missing fields to lorvex-workflow/src/task_update/input.rs so the Tauri / CLI surfaces accept the same patch shape, ` +
      `or mark them MCP-boundary-only in scripts/tests/contracts/repo_governance/task_update_field_parity.test.mjs (MCP_BOUNDARY_ONLY_FIELDS).`,
  );
  assert.deepEqual(
    onlyInWorkflow,
    [],
    `Fields present in workflow TaskUpdateInput but missing from MCP UpdateTaskArgs: ${onlyInWorkflow.join(', ')}.\n` +
      `Mirror the additions into mcp-server/src/contract/task/single_update.rs so the AI agents see the new patch shape.`,
  );

  // Defensive: the parser must actually find fields. A regex
  // regression that drops everything would silently make this test
  // pass against two empty sets.
  assert.ok(mcpFields.length >= 10, `Parsed only ${mcpFields.length} fields from MCP struct; regex likely broken`);
  assert.ok(
    workflowFields.length >= 10,
    `Parsed only ${workflowFields.length} fields from workflow struct; regex likely broken`,
  );
});

/**
 * Parse Tauri's `parse_update_payload` field-shape table and extract
 * the patch keys the IPC boundary accepts.
 *
 * The boundary deserializes into `TaskUpdateInput` so the structural
 * contract is the workflow's `FIELDS` slice — but the boundary also
 * accepts a `tags` alias (legacy renderer wire shape, rewritten to
 * `tags_set` before serde sees it) and rejects unknown shapes by
 * scanning a `FIELD_SHAPES` constant in command.rs. Parse that
 * constant so adding a new field there without a matching workflow
 * field, or vice versa, fails CI.
 */
function extractTauriBoundaryFields() {
  const source = readFileSync(TAURI_COMMAND_PATH, 'utf8');
  const tableRe = /const FIELD_SHAPES:\s*&\[FieldKind\]\s*=\s*&\[([\s\S]*?)\];/m;
  const match = source.match(tableRe);
  assert.ok(
    match,
    `${TAURI_COMMAND_PATH} must declare 'const FIELD_SHAPES: &[FieldKind] = &[ ... ];'`,
  );
  const body = match[1];
  const fields = [];
  for (const line of body.split('\n')) {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('//')) {
      continue;
    }
    // ("field_name", VariantName),
    const fieldMatch = trimmed.match(/^\(\s*"([a-z_][a-z_0-9]*)"\s*,/);
    if (fieldMatch) {
      fields.push(fieldMatch[1]);
    }
  }
  return fields;
}

// Tauri-only patch keys the workflow input doesn't model (and won't):
// pre-translation aliases that `parse_update_payload` rewrites into a
// workflow key before serde deserializes.
const TAURI_BOUNDARY_ONLY_FIELDS = new Set([
  // Legacy renderer wire shape — `parse_update_payload` rewrites this
  // to `tags_set` before deserializing into the workflow input.
  'tags',
]);

test('Tauri IPC update_task accepts the same field set as the workflow input', () => {
  const tauriFields = extractTauriBoundaryFields();
  const workflowFields = extractStructFields(WORKFLOW_INPUT_PATH, 'TaskUpdateInput');

  const tauriSet = new Set(
    tauriFields.filter((f) => !TAURI_BOUNDARY_ONLY_FIELDS.has(f)),
  );
  // The workflow input's `id` is filled in by the IPC adapter from the
  // URL/arg, so the boundary table doesn't list it.
  const workflowSet = new Set(workflowFields.filter((f) => f !== 'id'));

  const onlyInTauri = [...tauriSet].filter((f) => !workflowSet.has(f)).sort();
  const onlyInWorkflow = [...workflowSet].filter((f) => !tauriSet.has(f)).sort();

  assert.deepEqual(
    onlyInTauri,
    [],
    `Fields accepted by the Tauri update boundary but missing from workflow TaskUpdateInput: ${onlyInTauri.join(', ')}.\n` +
      `Add the missing fields to lorvex-workflow/src/task_update/input.rs, or mark them Tauri-boundary-only in ` +
      `scripts/tests/contracts/repo_governance/task_update_field_parity.test.mjs (TAURI_BOUNDARY_ONLY_FIELDS).`,
  );
  assert.deepEqual(
    onlyInWorkflow,
    [],
    `Fields present in workflow TaskUpdateInput but not accepted by the Tauri update boundary: ${onlyInWorkflow.join(', ')}.\n` +
      `Add an entry for each missing field to FIELD_SHAPES in app/src-tauri/src/commands/tasks/updates/command.rs so the IPC ` +
      `boundary surfaces a typed validation error instead of silently dropping the patch.`,
  );

  assert.ok(
    tauriFields.length >= 10,
    `Parsed only ${tauriFields.length} fields from Tauri FIELD_SHAPES; regex likely broken`,
  );
});
