import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');

test('CLI output JSON is selected only through the global --format option', () => {
  const argsSource = readRustSources('lorvex-cli/src/cli/args');
  const commandAndTranslateSource = readRustSources(
    'lorvex-cli/src/cli/command/mod.rs',
    'lorvex-cli/src/cli/translate',
    'lorvex-cli/src/dispatch/system.rs',
    'lorvex-cli/src/format_override/mod.rs',
  );

  assert.doesNotMatch(
    argsSource,
    /\bJsonOnly\b/,
    'CLI args should not keep a JsonOnly helper for per-command --json aliases',
  );
  assert.doesNotMatch(
    argsSource,
    /#\[arg\([^\]]*long\s*=\s*"json"[^\]]*\)\]\s*(?:pub\(in crate::cli\)\s*)?json:\s*bool/s,
    'CLI args should not define per-command --json output flags',
  );
  assert.doesNotMatch(
    argsSource,
    /#\[arg\([^\]]*short\s*=\s*'j'[^\]]*\)\]\s*(?:pub\(in crate::cli\)\s*)?json:\s*bool/s,
    'CLI args should not define per-command -j output flags',
  );
  assert.doesNotMatch(
    argsSource,
    /\bjson:\s*bool\b/,
    'CLI args should not retain command-local JSON output booleans',
  );
  assert.doesNotMatch(
    commandAndTranslateSource,
    /\bfrom_json_flag\b|\bargs\.json\b/,
    'CLI command translation should not branch on command-local JSON flags',
  );
});

test('CLI help and docs advertise --format json instead of removed --json aliases', () => {
  const userFacingSource = [
    'lorvex-cli/src/cli/args/mod.rs',
    'lorvex-cli/src/cli/args/tree.rs',
    'lorvex-cli/src/format_override/mod.rs',
    'docs/design/FEATURES.md',
    'scripts/install_cli.sh',
    'skill/SKILL.md',
  ]
    .map(read)
    .join('\n');

  assert.doesNotMatch(
    userFacingSource,
    /--json\b|(?:^|[\s`"'])-j(?:$|[\s`"',.;)])/m,
    'CLI help/docs should not advertise removed per-command JSON aliases',
  );
  assert.match(
    userFacingSource,
    /--format json/,
    'CLI help/docs should point script users to the global --format json option',
  );
});
