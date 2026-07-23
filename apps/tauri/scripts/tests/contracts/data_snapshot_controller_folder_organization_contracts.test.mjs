import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('data snapshot controller is organized as a coherent subtree with action modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/data/snapshot.ts'),
    'utf8',
  );
  const actionsEntrySource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/data/snapshot/actions/index.ts'),
    'utf8',
  );
  const actionsSource = readTypeScriptSources(
    'app/src/components/settings/controller/data/snapshot/actions',
  );
  const supportSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/data/snapshot/support.ts'),
    'utf8',
  );

  assert.match(rootSource, /useDataSnapshotActions\(/);
  assert.match(rootSource, /buildSnapshotPreview/);
  assert.doesNotMatch(
    rootSource,
    /void getRuntimePaths\(|const handleExportSnapshot = useCallback|const handleImportSnapshot = useCallback|void exportDataSnapshot\(\)\s*\.then/,
    'snapshot root should stay as a composition layer instead of inlining runtime bootstrap or transport actions',
  );

  // bootstrap.ts was removed — snapshot root manages state directly
  const bootstrapPath = path.join(repoRoot, 'app/src/components/settings/controller/data/snapshot/bootstrap.ts');
  assert.ok(
    !fs.existsSync(bootstrapPath),
    'snapshot bootstrap module should not exist — state management is handled directly in snapshot root',
  );

  assert.match(actionsEntrySource, /export function useDataSnapshotActions\(/);
  assert.match(actionsEntrySource, /useSnapshotPayloadActions\(/);
  assert.match(actionsEntrySource, /useSnapshotImportAction\(/);
  assert.doesNotMatch(
    actionsEntrySource,
    /exportDataSnapshot\(|importDataSnapshot\(|invalidateAllAfterSnapshotImport\(qc\)/,
    'snapshot actions entry should stay as a composition layer over the focused action modules',
  );

  assert.match(actionsSource, /exportDataSnapshot\(/);
  assert.match(actionsSource, /importDataSnapshot\(/);
  assert.match(actionsSource, /invalidateAllAfterSnapshotImport\(qc\)/);
  assert.match(
    actionsSource,
    /const blockingFindings = result\.validation_findings\.filter\([\s\S]*if \(blockingFindings\.length > 0\) \{[\s\S]*return;[\s\S]*\}\s*invalidateAllAfterSnapshotImport\(qc\);/,
    'snapshot import action should only invalidate query caches after scoped-import validation passes',
  );
  assert.doesNotMatch(
    actionsSource,
    /void getRuntimePaths\(|buildSnapshotPreview/,
    'snapshot actions module should stay focused on snapshot mutations rather than runtime bootstrap or derived preview logic',
  );

  assert.match(supportSource, /export interface DataSnapshotControls/);
  assert.match(supportSource, /setSnapshotBusy:/);
  assert.match(supportSource, /setSnapshotErrorDetail:/);
  assert.match(supportSource, /setLastSnapshotResult:/);
  assert.match(supportSource, /setSnapshotStatus:/);
  assert.match(supportSource, /setSnapshotFilePath:/);
  assert.match(supportSource, /export function getImportedTotal\(/);
});
