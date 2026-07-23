import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const read = (relPath) => fs.readFileSync(path.join(repoRoot, relPath), 'utf8');

test('snapshot import result keeps trust-relevant fields aligned across Tauri, TS IPC, and settings UI', () => {
  const tauriSource = read('app/src-tauri/src/commands/data/snapshot/import.rs');
  const ipcSource = read('app/src/lib/ipc/settings.ts');
  const panelSource = read('app/src/components/settings/data/SnapshotPanel.tsx');
  const importActionSource = read('app/src/components/settings/controller/data/snapshot/actions/import.ts');
  const strictParityLocales = JSON.parse(read('app/src/locales/strict-parity.json'));
  assert.ok(
    Array.isArray(strictParityLocales) && strictParityLocales.length >= 1,
    'strict-parity.json should define the first-class locale catalog set',
  );
  const strictParityCatalogs = strictParityLocales.map((localeCode) => [
    localeCode,
    JSON.parse(read(`app/src/locales/${localeCode}.json`)),
  ]);

  assert.match(
    tauriSource,
    /pub blobs_hash_mismatch: u64,/,
    'Tauri import result should expose blobs_hash_mismatch from the store summary',
  );
  assert.match(
    tauriSource,
    /blobs_hash_mismatch: summary\.blobs_hash_mismatch,/,
    'Tauri import command should preserve blobs_hash_mismatch in its IPC payload',
  );
  assert.match(
    ipcSource,
    /blobs_hash_mismatch: number;/,
    'TS IPC import result should expose blobs_hash_mismatch',
  );
  assert.match(
    panelSource,
    /blobs_hash_mismatch/,
    'SnapshotPanel should render blobs_hash_mismatch when present',
  );
  assert.match(
    panelSource,
    /settings\.importBlobsHashMismatch/,
    'SnapshotPanel should localize blobs_hash_mismatch copy rather than rendering a raw key or hard-coded string',
  );
  for (const [localeCode, catalog] of strictParityCatalogs) {
    assert.ok(
      Object.prototype.hasOwnProperty.call(catalog, 'settings.importBlobsHashMismatch'),
      `${localeCode}.json should define importBlobsHashMismatch so the summary stays localized`,
    );
  }
  assert.match(
    importActionSource,
    /if \(blockingFindings\.length > 0\) \{[\s\S]*return;\s*\}\s*invalidateAllAfterSnapshotImport\(qc\);/,
    'snapshot import action should invalidate caches only after confirming there are no blocking validation findings',
  );
});
