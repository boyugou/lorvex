import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import test from 'node:test';

// #4614 — the canonical task patch shape must agree between
// `TaskCreateInput` and `TaskUpdateInput` for every nullable scalar
// the two inputs share. Both live in `lorvex-workflow/src/task_*/
// input.rs` and both surface through the same MCP / Tauri / CLI
// triad. Pre-#4614, create used `Option<T>` while update used
// `Patch<T>` — so a field like `description` could not be wired
// through a shared helper without a per-input adapter. This test
// pins the wire-shape promotion: every shared nullable scalar must
// be `Patch<T>` in both inputs. Collection-shaped fields (`tags`,
// `depends_on`, `reminders`) are still `Option<Vec<_>>` because the
// tag / dependency patch shape is tracked separately under #4611;
// they're explicitly excluded from the parity gate below.

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..', '..', '..');

const CREATE_INPUT_PATH = resolve(
  REPO_ROOT,
  'lorvex-workflow/src/task_create/input.rs',
);
const UPDATE_INPUT_PATH = resolve(
  REPO_ROOT,
  'lorvex-workflow/src/task_update/input.rs',
);

/**
 * Parse a Rust struct and return a `Map<field, type>` for every
 * `pub[(crate)] name: Type,` line inside the named struct's body.
 * Attribute decorators and comments are skipped. The parser is
 * minimal — both targets are flat field lists with no nested types.
 */
function extractStructFieldTypes(filePath, structName) {
  const source = readFileSync(filePath, 'utf8');
  const structRe = new RegExp(
    `struct\\s+${structName}\\s*\\{([\\s\\S]*?)\\n\\}`,
    'm',
  );
  const match = source.match(structRe);
  assert.ok(match, `${filePath} must declare 'struct ${structName} { ... }'`);
  const body = match[1];
  const fields = new Map();
  for (const rawLine of body.split('\n')) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('//') || line.startsWith('#[')) {
      continue;
    }
    // pub[(crate)] name: Type,
    const fieldMatch = line.match(
      /^pub(?:\([a-z()]+\))?\s+([a-z_][a-z_0-9]*)\s*:\s*(.+?),?$/,
    );
    if (fieldMatch) {
      fields.set(fieldMatch[1], fieldMatch[2].trim());
    }
  }
  return fields;
}

// Fields that are NOT patch-shaped on either input by design:
// - `title` is required on create + NOT NULL in the schema, so update
//   exposes `Patch<String>` (and rejects `Clear` at the prep gate)
//   while create takes a bare `String` because there is no prior row
//   to fall back to.
// - `tags` / `depends_on` / `reminders` are collection-shaped; their
//   patch promotion is tracked under #4611.
// - `id` is identity, not patchable.
// - `completed` is a one-shot create-time flag (post-create completion
//   goes through the lifecycle owner, not update). Not on update.
const NON_PATCH_FIELDS = new Set([
  'id',
  'title',
  'tags',
  'depends_on',
  'reminders',
  'completed',
  // update-only set-vs-add-vs-remove triple
  'tags_set',
  'tags_add',
  'tags_remove',
  'depends_on_add',
  'depends_on_remove',
  // create-only flag
  // (none currently)
]);

test('TaskCreateInput and TaskUpdateInput agree on patch shape for every shared nullable scalar', () => {
  const create = extractStructFieldTypes(CREATE_INPUT_PATH, 'TaskCreateInput');
  const update = extractStructFieldTypes(UPDATE_INPUT_PATH, 'TaskUpdateInput');

  // Defensive: the parser must actually find fields.
  assert.ok(
    create.size >= 10,
    `Parsed only ${create.size} fields from TaskCreateInput; regex likely broken`,
  );
  assert.ok(
    update.size >= 10,
    `Parsed only ${update.size} fields from TaskUpdateInput; regex likely broken`,
  );

  // Every shared name that isn't on the NON_PATCH allow-list must
  // be `Patch<T>` in BOTH inputs.
  const sharedScalar = [...create.keys()].filter(
    (name) => update.has(name) && !NON_PATCH_FIELDS.has(name),
  );
  assert.ok(
    sharedScalar.length >= 5,
    `Expected at least 5 shared nullable scalars across create+update; got ${sharedScalar.length}: ${sharedScalar.join(', ')}`,
  );

  const mismatches = [];
  for (const name of sharedScalar) {
    const createTy = create.get(name);
    const updateTy = update.get(name);
    const isPatchCreate = /^Patch<.+>$/.test(createTy);
    const isPatchUpdate = /^Patch<.+>$/.test(updateTy);
    if (!isPatchCreate || !isPatchUpdate) {
      mismatches.push(
        `  - ${name}: create=${createTy} / update=${updateTy}`,
      );
    }
  }
  assert.deepEqual(
    mismatches,
    [],
    'Shared nullable scalar fields must use Patch<T> on both inputs ' +
      '(see lorvex-workflow/src/task_{create,update}/input.rs).\n' +
      `Mismatches:\n${mismatches.join('\n')}`,
  );
});

test('TaskCreateInput nullable scalars are Patch<T>, not bare Option<T>', () => {
  // Independent of the parity check, every Option<T> remaining on
  // `TaskCreateInput` must be either a collection (`Option<Vec<_>>`)
  // or the create-only `completed` boolean. A new `Option<String>` /
  // `Option<u8>` etc. is a regression.
  const create = extractStructFieldTypes(CREATE_INPUT_PATH, 'TaskCreateInput');
  const regressions = [];
  for (const [name, ty] of create) {
    if (!/^Option<.+>$/.test(ty)) {
      continue;
    }
    // Allow Option<Vec<_>> collections (tracked under #4611).
    if (/^Option<Vec<.+>>$/.test(ty)) {
      continue;
    }
    // Allow the one-shot create-time `completed` flag.
    if (name === 'completed' && ty === 'Option<bool>') {
      continue;
    }
    regressions.push(`  - ${name}: ${ty}`);
  }
  assert.deepEqual(
    regressions,
    [],
    'Nullable scalar fields on TaskCreateInput must use Patch<T> ' +
      '(see #4614). Remaining Option<T> fields:\n' +
      regressions.join('\n'),
  );
});
