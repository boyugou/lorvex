import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyEdgePath = path.join(repoRoot, 'lorvex-sync/src/apply/edge.rs');
const edgeDir = path.join(repoRoot, 'lorvex-sync/src/apply/edge');

test('lorvex-sync apply edge handlers stay split by edge family', () => {
  assert.equal(
    fs.existsSync(legacyEdgePath),
    false,
    'apply/edge.rs should not reappear as a mixed edge-handler hotspot',
  );

  const modSource = fs.readFileSync(path.join(edgeDir, 'mod.rs'), 'utf8');
  const childFiles = fs
    .readdirSync(edgeDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();

  assert.deepEqual(childFiles, [
    'dependency.rs',
    'habit_completion.rs',
    'helpers.rs',
    'mod.rs',
    'task_calendar_event_link.rs',
    'task_tag.rs',
    'tests.rs',
  ]);

  for (const moduleName of [
    'dependency',
    'habit_completion',
    'helpers',
    'task_calendar_event_link',
    'task_tag',
  ]) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `edge facade should register ${moduleName}.rs`,
    );
  }

  assert.match(
    modSource,
    /pub\(crate\) use dependency::\{apply_task_dependency_delete, apply_task_dependency_upsert\};/,
  );
  assert.match(
    modSource,
    /pub\(crate\) use task_tag::\{apply_task_tag_delete, apply_task_tag_upsert\};/,
  );

  const modLineCount = modSource.trimEnd().split('\n').length;
  assert.ok(modLineCount <= 40, `apply/edge/mod.rs should stay a thin facade, got ${modLineCount} lines`);

  for (const fileName of ['dependency.rs', 'habit_completion.rs', 'task_calendar_event_link.rs', 'task_tag.rs']) {
    const source = fs.readFileSync(path.join(edgeDir, fileName), 'utf8');
    assert.doesNotMatch(
      source,
      /mod tests|#\[cfg\(test\)\]/,
      `${fileName} should keep production handlers separate from tests.rs`,
    );
  }

  const dependencySource = fs.readFileSync(path.join(edgeDir, 'dependency.rs'), 'utf8');
  assert.match(dependencySource, /\nfn try_break_cycle_by_hlc\(/);
  assert.match(dependencySource, /\nfn find_cycle_path\(/);
});
