#!/usr/bin/env node

// Audit #2633: lock regression pins for the pure calendar/timezone
// math in `app/src/lib/dayContextMath.ts` — the functions that the
// "Weekend" / "Next Monday" quick-capture chips depend on. Prior to
// this verifier the repo had zero frontend tests, so the #2498
// Saturday-is-today fix and the DST-stable UTC anchoring could both
// silently regress.
//
// Runs the assertions in `day_context_math.test.ts` by invoking
// `node --experimental-strip-types` — works on Node 22.6+ (the
// engines-constrained floor for this repo).

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const testFile = path.join(scriptDir, 'day_context_math.test.ts');

const result = spawnSync(
  process.execPath,
  ['--experimental-strip-types', '--no-warnings=ExperimentalWarning', testFile],
  { stdio: 'inherit' },
);
if (result.error) {
  console.error(`[verify:day-context-math] failed to spawn node: ${result.error.message}`);
  process.exit(1);
}
process.exit(typeof result.status === 'number' ? result.status : 1);
