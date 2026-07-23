import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const envelopeRootPath = path.join(repoRoot, 'lorvex-sync/src/apply/envelope.rs');
const envelopeDir = path.join(repoRoot, 'lorvex-sync/src/apply/envelope');

test('lorvex-sync apply envelope stays split into explicit pipeline phases', () => {
  const rootSource = fs.readFileSync(envelopeRootPath, 'utf8');
  const lineCount = rootSource.trimEnd().split('\n').length;

  // After the redirect_flow split, redirect_flow is itself a folder with its
  // own per-concern siblings. The envelope/ top-level layout therefore mixes
  // .rs leaves (single-file phases) with one redirect_flow/ subdirectory.
  const entries = fs.readdirSync(envelopeDir, { withFileTypes: true });
  const childRsFiles = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith('.rs'))
    .map((entry) => entry.name)
    .sort();
  const childDirs = entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  assert.deepEqual(childRsFiles, [
    'delete_flow.rs',
    'dispatching.rs',
    'fk.rs',
    'lww_gate.rs',
    'payload_shadow.rs',
    'tombstone_gate.rs',
    'version.rs',
  ]);
  assert.deepEqual(childDirs, ['redirect_flow']);

  for (const moduleName of [
    'delete_flow',
    'dispatching',
    'fk',
    'lww_gate',
    'payload_shadow',
    'redirect_flow',
    'tombstone_gate',
    'version',
  ]) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }

  assert.ok(lineCount <= 220, `apply/envelope.rs should stay a thin coordinator, got ${lineCount} lines`);
  assert.match(rootSource, /\npub fn apply_envelope\(/);
  assert.doesNotMatch(
    rootSource,
    /\n(?:pub(?:\([^)]+\))?\s+)?fn\s+(?:check_fk_dependencies|get_local_version|apply_entity_with_version_mode|finalize_payload_shadow|gate_lww_and_fk|apply_redirected_tombstone|gate_existing_tombstone|finalize_entity_outcome)\(/,
    'apply/envelope.rs should not inline extracted phase helpers',
  );

  // redirect_flow split into mod, orchestrator, remap_envelope, delete_drop,
  // rewrite_payload, upsert_gate. Each function moved to its own sibling.
  const redirectFlowDir = path.join(envelopeDir, 'redirect_flow');
  const remapSource = fs.readFileSync(path.join(redirectFlowDir, 'remap_envelope.rs'), 'utf8');
  const deleteDropSource = fs.readFileSync(path.join(redirectFlowDir, 'delete_drop.rs'), 'utf8');
  const rewritePayloadSource = fs.readFileSync(path.join(redirectFlowDir, 'rewrite_payload.rs'), 'utf8');
  const upsertGateSource = fs.readFileSync(path.join(redirectFlowDir, 'upsert_gate.rs'), 'utf8');
  assert.match(remapSource, /\n(?:pub\([^)]+\)\s+)?fn build_remapped_envelope\(/);
  assert.match(deleteDropSource, /\n(?:pub\([^)]+\)\s+)?fn drop_redirected_delete\(/);
  assert.match(rewritePayloadSource, /\n(?:pub\([^)]+\)\s+)?fn rewrite_remapped_payload\(/);
  assert.match(upsertGateSource, /\n(?:pub\([^)]+\)\s+)?fn gate_redirected_upsert\(/);

  const lwwGateSource = fs.readFileSync(path.join(envelopeDir, 'lww_gate.rs'), 'utf8');
  assert.match(lwwGateSource, /\npub\(super\) fn gate_lww_and_fk\(/);
  assert.match(lwwGateSource, /record_lww_conflict_and_skip/);
  assert.match(lwwGateSource, /check_fk_dependencies/);

  const deleteFlowSource = fs.readFileSync(path.join(envelopeDir, 'delete_flow.rs'), 'utf8');
  assert.match(deleteFlowSource, /\npub\(super\) fn finalize_entity_outcome\(/);
});
