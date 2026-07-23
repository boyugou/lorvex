import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('mcp task recurrence runtime is organized as a focused module tree', () => {
  const recurrenceDir = path.join(repoRoot, 'mcp-server/src/tasks/recurrence');
  const modSource = fs.readFileSync(path.join(recurrenceDir, 'mod.rs'), 'utf8');
  const dateMathSource = fs.readFileSync(path.join(recurrenceDir, 'date_math.rs'), 'utf8');
  const ruleCodecSource = fs.readFileSync(path.join(recurrenceDir, 'rule_codec.rs'), 'utf8');

  assert.deepEqual(
    fs
      .readdirSync(recurrenceDir)
      .filter((entry) => entry.endsWith('.rs'))
      .sort(),
    ['date_math.rs', 'mod.rs', 'rule_codec.rs'],
    'server_task_recurrence/ should expose a focused recurrence module tree',
  );

  assert.match(modSource, /^mod date_math;$/m);
  assert.match(modSource, /^mod rule_codec;$/m);
  assert.match(modSource, /pub\(crate\) use date_math::/m);
  assert.match(modSource, /pub\(crate\) use rule_codec::/m);

  assert.doesNotMatch(modSource, /fn calculate_next_occurrence_date\(/);
  assert.doesNotMatch(modSource, /fn inject_bymonthday\(/);

  assert.match(dateMathSource, /calculate_next_occurrence_date/);
  assert.match(ruleCodecSource, /inject_bymonthday/);
});
