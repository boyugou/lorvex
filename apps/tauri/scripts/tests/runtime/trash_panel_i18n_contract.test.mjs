import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = process.cwd();

function readSource(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('TrashPanel uses locale-aware relative timestamps for archived rows', () => {
  const source = readSource('app/src/components/settings/data/TrashPanel.tsx');

  assert.match(
    source,
    /import \{ formatRelativeTime \} from '@\/lib\/dates\/dateLocale';/,
    'TrashPanel should reuse the shared locale-aware relative-time formatter',
  );
  assert.match(
    source,
    /formatRelativeTime\(\s*task\.archived_at,\s*locale,\s*t,\s*format,\s*timezone\s*\)/s,
    'TrashPanel rows should format archived_at through the active locale and timezone',
  );
  assert.doesNotMatch(
    source,
    /function formatRelative\(/,
    'TrashPanel should not keep a local locale-agnostic relative formatter',
  );
  assert.doesNotMatch(
    source,
    /'just now'|`[^`]*\$\{[^}]+\}[mhd] ago`/,
    'TrashPanel should not render hardcoded English relative-time fragments',
  );
});
