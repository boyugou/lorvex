import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const PANEL_ROOT = 'app/src/components/settings/data/DiagnosticsPanel.tsx';
const PANEL_SUBTREE = 'app/src/components/settings/data/diagnostics-panel';

test('DiagnosticsPanel delegates diagnostics UI sections to a folder-backed subtree', () => {
  const panelPath = path.join(repoRoot, PANEL_ROOT);
  const subtreePath = path.join(repoRoot, PANEL_SUBTREE);
  const panelSource = fs.readFileSync(panelPath, 'utf8');

  for (const fileName of [
    'ConflictLogSection.tsx',
    'ExportBundleCard.tsx',
    'FiltersCard.tsx',
    'LogsSections.tsx',
    'index.ts',
  ]) {
    assert.ok(
      fs.existsSync(path.join(subtreePath, fileName)),
      `diagnostics panel subtree should include ${fileName}`,
    );
  }

  assert.match(
    panelSource,
    /from '\.\/diagnostics-panel';/,
    'DiagnosticsPanel should import section components from the diagnostics-panel subtree',
  );
  assert.doesNotMatch(
    panelSource,
    /function (?:CircuitBreakerCard|ConflictLogSection|DeviceScopeFilter|ErrorLogsSection|ExportBundleCard|FiltersCard|RecentLogsSection|TimeWindowPicker)\b/,
    'DiagnosticsPanel root should not keep section component implementations inline',
  );
  assert.ok(
    panelSource.split('\n').length <= 180,
    'DiagnosticsPanel root should stay a small composition boundary after section extraction',
  );
});
