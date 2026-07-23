import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task attribution types and helpers live in a dedicated task_attribution module instead of the hotspot root', () => {
  const commandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  const taskAttributionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/attribution/mod.rs'),
    'utf8',
  );

  assert.doesNotMatch(
    commandsSource,
    /^pub use tasks::attribution::\{[\s\S]*get_task_attribution[\s\S]*AttributionActor[\s\S]*TaskAttribution[\s\S]*\};$/m,
    'commands.rs should not re-export task attribution IPC for handler registration',
  );
  assert.doesNotMatch(
    commandsSource,
    /\npub struct AttributionActor \{|\npub struct TaskAttribution \{|\nfn actor_human\(|\nfn actor_from_initiated_by\(|\nstruct TaskChangeEvent \{/,
    'commands.rs should not keep inline task attribution types or helper implementations after extraction',
  );
  assert.match(
    taskAttributionSource,
    /\npub struct AttributionActor \{[\s\S]*\npub struct TaskAttribution \{[\s\S]*\nstruct TaskChangeEvent \{[\s\S]*\nfn actor_human\([\s\S]*\nfn actor_from_initiated_by\([\s\S]*\npub fn get_task_attribution\(/,
    'task_attribution.rs should define the task attribution types and helper pipeline it owns',
  );
});
