import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('runtime sync-owner guard requires structured release panic hooks', () => {
  const guardSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-runtime/src/sync_owner/guard.rs'),
    'utf8',
  );
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-runtime/src/sync_owner/mod.rs'),
    'utf8',
  );
  const directOutputPattern =
    /\b(?:eprintln|eprint|println|print|dbg)!\s*\(|\b(?:write|writeln)!\s*\(\s*(?:&?\s*mut\s+)?(?:(?:std::io::|io::)?(?:stdout|stderr)\s*\(\s*\)|(?:stdout|stderr))|\b(?:std::io::|io::)?(?:stdout|stderr)\s*\(\s*\)/;

  assert.doesNotMatch(
    guardSource,
    directOutputPattern,
    'sync-owner guard must not fall back to direct stdout/stderr diagnostics',
  );
  assert.doesNotMatch(
    `${guardSource}\n${rootSource}`,
    /Option\s*<\s*ReleasePanicHook\s*>/,
    'sync-owner guard APIs must require an explicit release panic hook',
  );
  assert.doesNotMatch(
    `${guardSource}\n${rootSource}`,
    /\bon_release_panic:\s*None\b|,\s*None\s*,?\s*\)/,
    'sync-owner guard call sites and constructors must not preserve the legacy None hook fallback',
  );
  assert.match(guardSource, /on_release_panic:\s*ReleasePanicHook/);
});
