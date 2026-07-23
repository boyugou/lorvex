import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyPath = path.join(repoRoot, 'lorvex-store/src/import/apply/upserts/tasks.rs');
const moduleDir = path.join(repoRoot, 'lorvex-store/src/import/apply/upserts/tasks');

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), 'utf8');
}

test('store import task upserts are split into focused modules', () => {
  assert.ok(
    !fs.existsSync(legacyPath),
    'task import upserts should use tasks/mod.rs, not the old 900+ line tasks.rs hotspot',
  );

  const rootSource = read('mod.rs');
  assert.ok(
    rootSource.split('\n').length <= 80,
    'tasks/mod.rs should stay a small facade over focused task upsert modules',
  );

  for (const moduleName of ['aggregate', 'checklist', 'children', 'edges', 'tests']) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `tasks/mod.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under lorvex-store/src/import/apply/upserts/tasks/`,
    );
  }

  assert.match(rootSource, /^pub\(in crate::import::apply::upserts\) use aggregate::upsert_task;$/m);
  assert.match(rootSource, /pub\(in crate::import::apply::upserts\) use children::\{[\s\S]*?upsert_task_checklist_item[\s\S]*?upsert_task_reminder[\s\S]*?\};/);
  assert.match(rootSource, /pub\(in crate::import::apply::upserts\) use edges::\{[\s\S]*?upsert_task_calendar_event_link[\s\S]*?upsert_task_dependency[\s\S]*?upsert_task_tag[\s\S]*?\};/);

  assert.match(read('aggregate.rs'), /\npub\(in crate::import::apply::upserts\) fn upsert_task\b/);
  assert.match(read('edges.rs'), /\nfn upsert_task_tag\b|\npub\(in crate::import::apply::upserts\) fn upsert_task_tag\b/);
  assert.match(read('edges.rs'), /should_replace_versioned_composite/);
  assert.match(read('children.rs'), /\npub\(in crate::import::apply::upserts\) fn upsert_task_reminder\b/);
  assert.match(read('children.rs'), /\npub\(in crate::import::apply::upserts\) fn upsert_task_checklist_item\b/);
  assert.match(read('checklist.rs'), /\npub\(super\) fn parse_embedded_task_checklist_items\b/);
  assert.match(read('checklist.rs'), /\npub\(super\) fn materialize_task_checklist_items\b/);
  assert.match(read('tests.rs'), /\bfn\s+materialize_preserves_newer_local_checklist_item\b/);
});
