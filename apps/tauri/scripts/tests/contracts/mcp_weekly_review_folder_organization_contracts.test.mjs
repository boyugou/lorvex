import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('server_weekly_review is organized as a folder-backed subsystem with brief and snapshot modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/reviews/weekly/mod.rs'),
    'utf8',
  );
  const briefSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/reviews/weekly/brief.rs'),
    'utf8',
  );
  const snapshotSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/reviews/weekly/snapshot.rs'),
    'utf8',
  );

  assert.match(rootSource, /^mod brief;$/m);
  assert.match(rootSource, /^mod snapshot;$/m);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'brief',
    symbols: 'get_weekly_review_brief',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'snapshot',
    symbols: 'get_weekly_review_snapshot',
  }), true);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn get_weekly_review_brief\(|\npub\(crate\) fn get_weekly_review_snapshot\(|\nfn clamp_rows_text_field\(/,
    'server_weekly_review root should remain a composition root after folder extraction',
  );

  assert.match(briefSource, /\npub\(crate\) fn get_weekly_review_brief\(/);
  assert.match(snapshotSource, /\npub\(crate\) fn get_weekly_review_snapshot\(/);
  assert.match(
    snapshotSource,
    /use crate::system::diagnostics::clamp_rows_text_field;/,
    'weekly review snapshot should reuse the shared diagnostics row-clamp helper',
  );
  assert.doesNotMatch(
    snapshotSource,
    /\nfn clamp_rows_text_field\(/,
    'weekly review snapshot should not keep a local copy of the row-clamp helper',
  );
});
