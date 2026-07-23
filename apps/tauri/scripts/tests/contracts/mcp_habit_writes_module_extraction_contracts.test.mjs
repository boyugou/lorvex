import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('mcp server habit writes delegate mutation domains to focused submodules', () => {
  const writesFacadePath = path.join(repoRoot, 'mcp-server/src/habits/writes.rs');
  const writesFacadeSource = fs.readFileSync(writesFacadePath, 'utf8');
  const expectedModules = {
    completions: ['complete_habit', 'uncomplete_habit', 'batch_complete_habit'],
    create_update: ['create_habit', 'UpdateHabitParams', 'update_habit'],
    delete: ['delete_habit'],
    tests: ['delete_habit_emits_tombstones_for_completions'],
  };

  for (const [moduleName, symbols] of Object.entries(expectedModules)) {
    // `tests` is now a folder-backed submodule (`writes/tests/mod.rs` +
    // per-domain test files); the other domains stay as flat `<name>.rs`.
    const flatPath = path.join(
      repoRoot,
      'mcp-server/src/habits/writes',
      `${moduleName}.rs`,
    );
    const folderModPath = path.join(
      repoRoot,
      'mcp-server/src/habits/writes',
      moduleName,
      'mod.rs',
    );
    const modulePath = fs.existsSync(flatPath) ? flatPath : folderModPath;
    assert.ok(
      fs.existsSync(modulePath),
      `server_habits/writes/${moduleName}.rs should own ${moduleName} habit write contracts`,
    );
    assert.match(
      writesFacadeSource,
      new RegExp(`mod ${moduleName};`),
      `server_habits/writes.rs should declare ${moduleName} submodule`,
    );

    // For folder-backed modules, expand the source to include sibling
    // files so symbols owned by per-domain test files (e.g. `tests/delete_habit.rs`)
    // count toward the contract.
    const folderDir = path.dirname(folderModPath);
    let moduleSource = fs.readFileSync(modulePath, 'utf8');
    if (modulePath === folderModPath && fs.existsSync(folderDir)) {
      moduleSource = fs
        .readdirSync(folderDir)
        .filter((name) => name.endsWith('.rs'))
        .map((name) => fs.readFileSync(path.join(folderDir, name), 'utf8'))
        .join('\n');
    }
    for (const symbol of symbols) {
      assert.match(
        moduleSource,
        new RegExp(`\\b${symbol}\\b`),
        `server_habits/writes/${moduleName}.rs should own ${symbol}`,
      );
      assert.doesNotMatch(
        writesFacadeSource,
        new RegExp(`\\b(?:pub\\(crate\\)\\s+)?(?:fn|struct)\\s+${symbol}\\b`),
        `server_habits/writes.rs should not keep inline ${symbol} definitions after extraction`,
      );
    }
  }

  assert.match(
    writesFacadeSource,
    /pub\(crate\) use completions::\{[\s\S]*batch_complete_habit[\s\S]*complete_habit[\s\S]*uncomplete_habit[\s\S]*\};/,
    'writes facade should re-export completion write contracts',
  );
  assert.match(
    writesFacadeSource,
    /pub\(crate\) use create_update::\{[\s\S]*create_habit[\s\S]*update_habit[\s\S]*UpdateHabitParams[\s\S]*\};/,
    'writes facade should re-export create/update write contracts',
  );
  assert.match(
    writesFacadeSource,
    /pub\(crate\) use delete::delete_habit;/,
    'writes facade should re-export delete_habit',
  );
});
