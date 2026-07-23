import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('lorvex-sync outbox stays split into focused queue modules', () => {
  const outboxDir = path.join(repoRoot, 'lorvex-sync/src/outbox');
  const modSource = fs.readFileSync(path.join(outboxDir, 'mod.rs'), 'utf8');

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'lorvex-sync/src/outbox.rs')),
    false,
    'outbox.rs should not reappear as a mixed queue engine',
  );

  for (const moduleName of [
    'coalesce',
    'constants',
    'enqueue',
    'error',
    'gc',
    'mutation',
    'query',
    'retry',
    'types',
  ]) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `outbox facade should register the ${moduleName} module`,
    );
    // Each registered module must resolve to either outbox/<name>.rs (single
    // file) or outbox/<name>/mod.rs (further split into per-concern siblings).
    // E.g. coalesce.rs has been split into coalesce/{mod,enqueue,warn_dedup}.rs.
    const asFile = path.join(outboxDir, `${moduleName}.rs`);
    const asFolderMod = path.join(outboxDir, moduleName, 'mod.rs');
    assert.equal(
      fs.existsSync(asFile) || fs.existsSync(asFolderMod),
      true,
      `outbox/${moduleName}.rs or outbox/${moduleName}/mod.rs should exist`,
    );
  }

  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'enqueue',
      symbols: ['enqueue'],
    }),
    true,
    'outbox facade should re-export plain enqueue operations',
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'coalesce',
      symbols: ['enqueue_coalesced'],
    }),
    true,
    'outbox facade should re-export coalescing operations',
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'retry',
      symbols: [
        'record_retry',
        'record_many_retries',
        'mark_permanently_failed',
        'reset_retry_counts_for_transport_switch',
        'reset_row_retry_count',
      ],
    }),
    true,
    'outbox facade should re-export retry operations',
  );

  for (const forbiddenSnippet of [
    'pub fn enqueue(',
    'pub fn get_pending(',
    'pub fn drain_pending_inbox(',
    'pub fn record_retry(',
    'fn enqueue_coalesced_body(',
  ]) {
    assert.equal(
      modSource.includes(forbiddenSnippet),
      false,
      `outbox facade should not inline queue behavior: ${forbiddenSnippet}`,
    );
  }
});

test('lorvex-sync pending inbox stays split into focused queue modules', () => {
  const pendingDir = path.join(repoRoot, 'lorvex-sync/src/pending_inbox');
  const modSource = fs.readFileSync(path.join(pendingDir, 'mod.rs'), 'utf8');

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'lorvex-sync/src/pending_inbox.rs')),
    false,
    'pending_inbox.rs should not reappear as a mixed queue engine',
  );

  for (const moduleName of [
    'diagnostics',
    'drain',
    'enqueue',
    'quarantine',
    'remap',
    'store',
    'types',
  ]) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `pending_inbox facade should register ${moduleName}.rs`,
    );
    assert.equal(
      fs.existsSync(path.join(pendingDir, `${moduleName}.rs`)),
      true,
      `pending_inbox/${moduleName}.rs should exist`,
    );
  }

  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'enqueue',
      symbols: ['enqueue_deferred', 'enqueue_pending'],
    }),
    true,
    'pending_inbox facade should re-export enqueue operations',
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'store',
      symbols: [
        'get_all_pending',
        'remove_pending',
        'has_expired_entries',
        'gc_expired_entries',
        'record_reattempt',
        'record_reattempt_busy',
        'record_reattempt_with_error',
        'count_pending',
        'has_pending_for_target',
      ],
    }),
    true,
    'pending_inbox facade should re-export store/bookkeeping operations',
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'drain',
      symbols: ['drain_pending_inbox'],
    }),
    true,
    'pending_inbox facade should re-export the drain engine',
  );

  for (const forbiddenSnippet of [
    'pub fn enqueue_pending(',
    'pub fn drain_pending_inbox(',
    'fn remap_missing_dependency(',
    'fn sync_error_for_pending_apply_failure(',
  ]) {
    assert.equal(
      modSource.includes(forbiddenSnippet),
      false,
      `pending_inbox facade should not inline queue behavior: ${forbiddenSnippet}`,
    );
  }
});
