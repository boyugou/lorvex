import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_import keeps entity import loops in a coherent folder-backed module tree', () => {
  // server_import was consolidated into server_import_export.rs which delegates
  // to lorvex_store for the heavy lifting (export_to_zip / import_from_zip).
  const importExportPath = path.join(repoRoot, 'mcp-server/src/workflow/import_export/mod.rs');
  const importExportSource = fs.readFileSync(importExportPath, 'utf8');

  assert.ok(
    fs.existsSync(importExportPath),
    'server_import_export.rs should exist as the MCP import/export surface',
  );
  assert.match(
    importExportSource,
    /fn import_data\(/,
    'server_import_export.rs should expose an import_data tool',
  );
  assert.match(
    importExportSource,
    /fn export_all_data\(/,
    'server_import_export.rs should expose an export_all_data tool',
  );
  assert.match(
    importExportSource,
    /lorvex_store::import_from_zip/,
    'server_import_export.rs should delegate import to lorvex_store',
  );
  assert.match(
    importExportSource,
    /lorvex_store::export_to_zip/,
    'server_import_export.rs should delegate export to lorvex_store',
  );
});
