// Contract test (issue #4346): every Tauri IPC surface that touches
// the canonical task `write::*` SQL primitives or enqueues a task
// upsert / task delete MUST route the write through an
// `IpcMutationExecutor` entry point (`execute_ipc_mutation_with_finalizer`
// or `execute_ipc_entity_mutation`) inside a `Mutation<M>` `apply`
// body.
//
// The migration to that single pipeline (PR #4468 → this PR, closing
// #4346) is the foundation Core Design Rule 2 stands on: every Tauri
// write must share the same six-step contract — pre-snapshot, HLC
// mint, row write, outbox enqueue, `local_change_seq++`, event_bus
// broadcast — that the MCP server and CLI surfaces apply. A
// surface-level file that calls `task::write::hard_delete_task_lww`
// or `task::write::apply_task_update` without declaring its
// `impl Mutation for` descriptor and `execute_ipc_*` adapter call
// silently bypasses the pipeline: the HLC stamp escapes any
// surrounding session, `local_change_seq` is never bumped, and the
// event_bus emit is left to the call site (or forgotten).
//
// The verifier enforces a coupling rule at the file level: every
// production Rust file under `app/src-tauri/src` that references
// `lorvex_store::repositories::task::write::` or
// `enqueue_task_upsert(` / `enqueue_task_delete_with_version(`
// MUST also contain:
//
//   1. an `impl Mutation for` block (the `Mutation<M>` descriptor),
//   2. and an `execute_ipc_mutation_with_finalizer` or
//      `execute_ipc_entity_mutation` call (the executor adapter).
//
// Files in the explicit `ROUTED_THROUGH_HELPER` allowlist instead
// route their writes through an internal helper that owns the
// `Mutation<M>` boilerplate (e.g. the `dependencies/atomic.rs`
// pattern that re-routes through `enqueue_task_upsert` inside the
// finalizer of a sibling-file mutation). Each allowlist entry MUST
// have a one-line justification.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

const TAURI_SRC_ROOT = 'app/src-tauri/src';

// Forbidden surface-level tokens. Their presence in a production
// (non-test) file means the file touches the canonical task write
// pipeline; the file MUST therefore declare `impl Mutation for` +
// `execute_ipc_*` to prove the write is routed through the
// executor.
const FORBIDDEN_TOKENS = [
  // Canonical store-layer SQL writers — any direct reference at the
  // Tauri surface must be wrapped in a `Mutation<M>` descriptor.
  'lorvex_store::repositories::task::write::hard_delete_task_lww',
  'lorvex_store::repositories::task::write::apply_task_update',
  'lorvex_store::repositories::task::write::TaskUpdatePatch',
  // Task-row outbox enqueue helpers — outside the executor's
  // finalizer slot they bypass `local_change_seq++` and the
  // event_bus broadcast.
  'enqueue_task_upsert(',
  'enqueue_task_delete_with_version(',
];

// Required adoption markers. A file that touches a forbidden token
// MUST contain BOTH of these (one descriptor declaration, one
// executor entry call).
const REQUIRED_DESCRIPTOR_RE = /impl(?:<[^>]*>)?\s+Mutation\s+for\b/;
const REQUIRED_EXECUTOR_RE =
  /execute_ipc_(?:mutation_with_finalizer|entity_mutation)\s*\(/;

// Files where every forbidden-token occurrence sits inside an
// internal helper that itself routes the write through an external
// `Mutation<M>` / `execute_ipc_*` pair owned by a sibling file.
// Each entry MUST justify why the file's writes are still inside the
// executor pipeline despite the file not declaring the markers
// itself.
const ROUTED_THROUGH_HELPER = new Map([
  // `tasks/mod.rs` re-exports the enqueue helpers as module-level
  // `use` items and has one `enqueue_task_upsert` call inside the
  // surrounding lifecycle bookkeeping helper that runs INSIDE the
  // cancel/complete `Mutation::apply` finalizer (its caller is
  // `lifecycle/removal/cancel.rs`'s descriptor, which provides the
  // `impl Mutation for` + `execute_ipc_*` adoption).
  [`${TAURI_SRC_ROOT}/commands/tasks/mod.rs`,
    're-exports + finalizer-internal lifecycle bookkeeping called from sibling Mutation descriptors'],
  // `tasks/updates.rs` is the legacy file-level re-export shim — the
  // canonical `update_task` IPC adoption lives under
  // `tasks/updates/command.rs` + `flush.rs` (`IpcTaskUpdateFlush`).
  [`${TAURI_SRC_ROOT}/commands/tasks/updates.rs`,
    're-export shim; canonical descriptor lives in updates/command.rs'],
  // `tasks/lifecycle/deferral.rs` enqueues reminder upserts (not
  // task upserts) and threads through the canonical
  // `task_deferral::defer_task` workflow op; its task writes are
  // owned by the surrounding `Mutation` descriptors in the batch
  // and single-task surfaces.
  [`${TAURI_SRC_ROOT}/commands/tasks/lifecycle/deferral.rs`,
    'reminder-only finalizer helper; task writes owned by sibling Mutation descriptors'],
  // `tasks/dependencies/mod.rs` re-exports `enqueue_task_upsert` as
  // a module-level `use` for the sibling `atomic.rs` file, which
  // owns the `Mutation` descriptor + `execute_ipc_*` adoption.
  [`${TAURI_SRC_ROOT}/commands/tasks/dependencies/mod.rs`,
    're-exports enqueue helper consumed inside atomic.rs Mutation descriptors'],
  // `tasks/lifecycle/removal/cascade.rs` only enqueues
  // focus_schedule / current_focus upserts (not task upserts);
  // those calls run inside the cancel/permanent/purge `Mutation`
  // finalizers in sibling files.
  [`${TAURI_SRC_ROOT}/commands/tasks/lifecycle/removal/cascade.rs`,
    'focus-plan enqueue helper invoked from sibling removal Mutation descriptors'],
  // `tasks/privacy/mod.rs` is `#[cfg(test)]`-only after #2940-H1.
  // The detector's cfg-test-block elision keeps its production
  // surface empty, but the file-level `use` line still pulls in
  // `enqueue_task_upsert`; the dead `clear_all_raw_input_with_conn`
  // helper survives only as test scaffold.
  [`${TAURI_SRC_ROOT}/commands/tasks/privacy/mod.rs`,
    'test-only helper after #2940-H1; production surface removed'],
  // `commands.rs` (the top-level commands module) re-exports every
  // `enqueue_*` helper as `pub(crate)` for sibling consumption.
  // The re-exports are inert until called; every caller is covered
  // by its own file-level entry in this verifier.
  [`${TAURI_SRC_ROOT}/commands.rs`,
    'top-level re-export module; enqueue helpers consumed by sibling files'],
  // The queue-primitive layer — these files DEFINE the `enqueue_*`
  // helpers themselves (and the surrounding lifecycle-plan batch
  // helpers); the executor sits ABOVE this layer and calls into it
  // from inside `Mutation` finalizers. The verifier flags surface
  // callers, not the underlying primitives.
  [`${TAURI_SRC_ROOT}/commands/sync/runtime/queue/enqueue_lifecycle.rs`,
    'queue-primitive layer; defines + composes enqueue helpers consumed by executor finalizers'],
  [`${TAURI_SRC_ROOT}/commands/sync/runtime/queue/enqueue_task_entities.rs`,
    'queue-primitive layer; defines task enqueue helpers consumed by executor finalizers'],
  [`${TAURI_SRC_ROOT}/commands/sync/runtime/queue/seed_entities.rs`,
    'queue-primitive layer; seeds initial-state outbox rows before the executor pipeline boots'],
  // `tasks/updates/flush.rs` is the `IpcTaskUpdateFlush` backend
  // implementation — the canonical `lorvex_workflow::task_update`
  // flush callback. Its enqueue calls run INSIDE the
  // `flush_with_backend` body that the sibling `command.rs` invokes
  // alongside the workflow's `update_task` op (#4451), so the writes
  // are still part of one surface-mutation event.
  [`${TAURI_SRC_ROOT}/commands/tasks/updates/flush.rs`,
    'TaskUpdateFlushBackend impl; enqueue calls run inside workflow flush invoked from command.rs'],
  // `tasks/dependencies/atomic.rs` adopts the executor through
  // `execute_ipc_mutation_with_finalizer` and constructs
  // `AddTaskDependencyMutation` / `RemoveTaskDependencyMutation`
  // descriptors whose `impl Mutation for` lives in the canonical
  // `lorvex_workflow::task_dependency_edges` module — the verifier
  // only scans the Tauri tree for the impl marker, so the typed
  // workflow-owned descriptor is invisible to it. The `enqueue_task_upsert`
  // calls run INSIDE the finalizer closure that the executor invokes.
  [`${TAURI_SRC_ROOT}/commands/tasks/dependencies/atomic.rs`,
    'workflow-owned Mutation descriptor invoked through executor finalizer'],
]);

function walkRustFiles(absoluteRoot) {
  if (!fs.existsSync(absoluteRoot)) return [];
  const results = [];
  for (const entry of fs.readdirSync(absoluteRoot, { withFileTypes: true })) {
    const full = path.join(absoluteRoot, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'target' || entry.name === '.git' || entry.name === 'tests') {
        continue;
      }
      results.push(...walkRustFiles(full));
    } else if (entry.isFile() && entry.name.endsWith('.rs')) {
      if (entry.name === 'tests.rs') continue;
      results.push(full);
    }
  }
  return results;
}

function relativePosix(absolutePath) {
  return path.relative(repoRoot, absolutePath).split(path.sep).join('/');
}

/**
 * Strip `#[cfg(test)] mod tests { ... }` blocks from the source so the
 * detector only inspects production code. Walks brace depth from the
 * test-module entry; lines inside the block contribute neither
 * forbidden-token findings nor required-marker matches.
 */
function stripCfgTestModules(source) {
  const lines = source.split('\n');
  const kept = [];
  let inTestBlock = 0;
  let testBraceBudget = null;

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];

    if (testBraceBudget != null) {
      for (const ch of raw) {
        if (ch === '{') inTestBlock++;
        else if (ch === '}') inTestBlock--;
      }
      if (inTestBlock <= testBraceBudget) {
        testBraceBudget = null;
        inTestBlock = 0;
      }
      continue;
    }

    if (/#\[cfg\(test\)\]/.test(raw)) {
      for (let j = i; j < Math.min(i + 3, lines.length); j++) {
        if (/\bmod\s+\w+\s*\{/.test(lines[j] ?? '')) {
          testBraceBudget = inTestBlock;
          for (const ch of lines[j]) {
            if (ch === '{') inTestBlock++;
            else if (ch === '}') inTestBlock--;
          }
          i = j;
          break;
        }
      }
      if (testBraceBudget != null) continue;
    }

    kept.push(raw);
  }
  return kept.join('\n');
}

function stripCommentsAndStrings(source) {
  // Remove line comments and block comments so a literal forbidden
  // token sitting inside a docstring or `//`-comment isn't flagged.
  // String literals are preserved because they are vanishingly rare
  // carriers of these tokens (the canonical store path is reached
  // through a Rust path expression, not a string).
  let result = source.replace(/\/\*[\s\S]*?\*\//g, '');
  result = result
    .split('\n')
    .map((line) => {
      const idx = line.indexOf('//');
      if (idx === -1) return line;
      // Preserve `//!` (inner doc) and `///` (outer doc) start tokens
      // for the detector even though their content is also a comment;
      // splitting on `//` strips them along with the prose.
      return line.slice(0, idx);
    })
    .join('\n');
  return result;
}

function findTokenOccurrences(source, token) {
  const findings = [];
  const needle = token;
  let idx = source.indexOf(needle);
  while (idx !== -1) {
    findings.push(idx);
    idx = source.indexOf(needle, idx + needle.length);
  }
  return findings;
}

test('Tauri files touching task `write::*` SQL primitives or task-row enqueue helpers must adopt the IpcMutationExecutor pipeline', () => {
  const absoluteRoot = path.join(repoRoot, TAURI_SRC_ROOT);
  const findings = [];

  for (const file of walkRustFiles(absoluteRoot)) {
    const relative = relativePosix(file);
    if (ROUTED_THROUGH_HELPER.has(relative)) continue;

    const raw = fs.readFileSync(file, 'utf8');
    const productionOnly = stripCfgTestModules(raw);
    const scannable = stripCommentsAndStrings(productionOnly);

    const tokenHits = [];
    for (const token of FORBIDDEN_TOKENS) {
      if (findTokenOccurrences(scannable, token).length > 0) {
        tokenHits.push(token);
      }
    }
    if (tokenHits.length === 0) continue;

    const hasDescriptor = REQUIRED_DESCRIPTOR_RE.test(scannable);
    const hasExecutor = REQUIRED_EXECUTOR_RE.test(scannable);

    if (!hasDescriptor || !hasExecutor) {
      findings.push({
        file: relative,
        tokens: tokenHits,
        hasDescriptor,
        hasExecutor,
      });
    }
  }

  if (findings.length > 0) {
    const detail = findings
      .map((f) => (
        `  ${f.file}\n` +
        `    forbidden tokens: ${f.tokens.join(', ')}\n` +
        `    impl Mutation for present: ${f.hasDescriptor}\n` +
        `    execute_ipc_*    present: ${f.hasExecutor}`
      ))
      .join('\n');
    assert.fail(
      `Found ${findings.length} Tauri surface file(s) that reference the canonical task write pipeline\n` +
        `without adopting the IpcMutationExecutor contract (closing #4346).\n\n` +
        `Every such file must EITHER:\n` +
        `  1. declare an \`impl Mutation for\` descriptor AND call \`execute_ipc_mutation_with_finalizer\`\n` +
        `     or \`execute_ipc_entity_mutation\` to route the write through the executor;\n` +
        `  2. or be added to \`ROUTED_THROUGH_HELPER\` in this verifier with a one-line\n` +
        `     justification explaining which sibling file owns the descriptor.\n\n` +
        detail,
    );
  }
});

test('IpcMutationExecutor adoption detector flags a synthetic Tauri file that imports task::write::* without Mutation adoption', () => {
  const synthetic = `
use lorvex_store::repositories::task::write::apply_task_update;
pub fn bad(conn: &rusqlite::Connection) {
    apply_task_update(conn, &patch).unwrap();
    enqueue_task_upsert(conn, &task).unwrap();
}
`;
  const scannable = stripCommentsAndStrings(stripCfgTestModules(synthetic));
  const hits = FORBIDDEN_TOKENS.filter(
    (token) => findTokenOccurrences(scannable, token).length > 0,
  );
  assert.ok(hits.length > 0, 'detector must find forbidden tokens in synthetic surface code');
  assert.equal(REQUIRED_DESCRIPTOR_RE.test(scannable), false);
  assert.equal(REQUIRED_EXECUTOR_RE.test(scannable), false);
});

test('IpcMutationExecutor adoption detector accepts a synthetic file that declares both markers', () => {
  const synthetic = `
use lorvex_store::repositories::task::write::apply_task_update;

struct FooMutation;
impl<'a> Mutation for FooMutation {
    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        apply_task_update(conn, &patch)?;
        Ok(MutationOutput::new(serde_json::json!({}), "ok".into()))
    }
}

pub fn entry(conn: &Connection) -> AppResult<()> {
    let m = FooMutation;
    execute_ipc_mutation_with_finalizer(conn, &m, Entity::Task, |c, _| {
        enqueue_task_upsert(c, &task)?;
        Ok(())
    })?;
    Ok(())
}
`;
  const scannable = stripCommentsAndStrings(stripCfgTestModules(synthetic));
  assert.equal(REQUIRED_DESCRIPTOR_RE.test(scannable), true);
  assert.equal(REQUIRED_EXECUTOR_RE.test(scannable), true);
});

test('IpcMutationExecutor adoption detector ignores cfg(test) mod tests blocks', () => {
  const synthetic = `
pub fn ok() {}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_store::repositories::task::write::apply_task_update;
    #[test]
    fn fixture() {
        apply_task_update(conn, &patch).unwrap();
    }
}
`;
  const productionOnly = stripCfgTestModules(synthetic);
  const scannable = stripCommentsAndStrings(productionOnly);
  const hits = FORBIDDEN_TOKENS.filter(
    (token) => findTokenOccurrences(scannable, token).length > 0,
  );
  assert.equal(
    hits.length,
    0,
    'detector must not flag forbidden tokens inside cfg(test) mod tests blocks',
  );
});
