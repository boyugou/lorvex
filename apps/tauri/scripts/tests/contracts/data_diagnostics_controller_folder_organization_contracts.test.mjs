import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('data diagnostics controller is organized as a folder-backed subsystem with focused refresh, recent-log, and action modules', () => {
  const diagnosticsRoot = path.join(repoRoot, 'app/src/components/settings/controller/data/diagnostics');
  const diagnosticsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/data/diagnostics.ts'),
    'utf8',
  );
  const diagnosticsTreeSource = readTypeScriptSources(
    'app/src/components/settings/controller/data/diagnostics.ts',
    'app/src/components/settings/controller/data/diagnostics',
  );

  for (const fileName of ['actions.ts', 'recentLogs.ts', 'refresh.ts', 'types.ts']) {
    assert.ok(
      fs.existsSync(path.join(diagnosticsRoot, fileName)),
      `data diagnostics subtree should include ${fileName}`,
    );
  }

  assert.match(diagnosticsSource, /from '\.\/diagnostics\/actions';/);
  assert.match(diagnosticsSource, /from '\.\/diagnostics\/recentLogs';/);
  assert.match(diagnosticsSource, /from '\.\/diagnostics\/refresh';/);
  assert.match(diagnosticsSource, /from '\.\/diagnostics\/types';/);
  assert.doesNotMatch(
    diagnosticsSource,
    /getErrorLogs\(200\)|navigator\.clipboard\.writeText|window\.confirm\(/,
    'data diagnostics root should stay a composition boundary once refresh and action logic move into dedicated modules',
  );

  assert.match(diagnosticsTreeSource, /export function useDataDiagnosticsRefresh\(/);
  assert.match(diagnosticsTreeSource, /export function useRecentLogs\(/);
  assert.match(diagnosticsTreeSource, /export function useDataDiagnosticsActions\(/);
  assert.match(diagnosticsTreeSource, /const \[entries, changelog, (?:syncEvents|filteredSyncEvents)\] = await Promise\.all\(\[/);
  assert.match(diagnosticsTreeSource, /const handleClearErrorLogs = useCallback\(async \(\) => \{/);
});
