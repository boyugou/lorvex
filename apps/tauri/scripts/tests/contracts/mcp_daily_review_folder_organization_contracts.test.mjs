import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, readRustSources, repoRoot } from './shared.mjs';

test('daily review runtime lives in a coherent folder-backed module tree', () => {
  const subsystemDir = path.join(repoRoot, 'mcp-server/src/reviews/daily');
  const modPath = path.join(subsystemDir, 'mod.rs');
  const readsPath = path.join(subsystemDir, 'reads.rs');
  const writesRootPath = path.join(subsystemDir, 'writes/mod.rs');
  const addPath = path.join(subsystemDir, 'writes/add.rs');
  const amendPath = path.join(subsystemDir, 'writes/amend.rs');
  const testsPath = path.join(subsystemDir, 'tests.rs');
  const legacyFlatPath = path.join(repoRoot, 'mcp-server/src/reviews/daily.rs');

  for (const filePath of [modPath, readsPath, writesRootPath, addPath, amendPath, testsPath]) {
    assert.ok(
      fs.existsSync(filePath),
      `${path.relative(repoRoot, filePath)} should exist as part of the daily review subsystem`,
    );
  }

  assert.ok(
    !fs.existsSync(legacyFlatPath),
    'server_daily_review.rs should be replaced by a folder-backed module tree once the subsystem is decomposed',
  );

  const modSource = fs.readFileSync(modPath, 'utf8');
  const readsSource = fs.readFileSync(readsPath, 'utf8');
  const writesRootSource = fs.readFileSync(writesRootPath, 'utf8');
  const writesSource = readRustSources(
    'mcp-server/src/reviews/daily/writes/mod.rs',
    'mcp-server/src/reviews/daily/writes/add.rs',
    'mcp-server/src/reviews/daily/writes/amend.rs',
  );

  assert.match(modSource, /mod reads;/);
  assert.match(modSource, /mod writes;/);
  assert.ok(
    hasRustUseReexport(modSource, {
      modulePath: 'reads',
      symbols: ['get_daily_review', 'get_review_history'],
      visibility: 'pub(crate)',
    }),
    'daily review root should re-export read helpers from reads.rs',
  );
  assert.ok(
    hasRustUseReexport(modSource, {
      modulePath: 'writes',
      symbols: ['add_daily_review', 'amend_daily_review'],
      visibility: 'pub(crate)',
    }),
    'daily review root should re-export write helpers from writes/mod.rs',
  );
  assert.match(writesRootSource, /^mod add;$/m);
  assert.match(writesRootSource, /^mod amend;$/m);
  assert.ok(
    hasRustUseReexport(writesRootSource, {
      modulePath: 'add',
      symbols: 'add_daily_review',
      visibility: 'pub(crate)',
    }),
    'daily review writes root should re-export add_daily_review from add.rs',
  );
  assert.ok(
    hasRustUseReexport(writesRootSource, {
      modulePath: 'amend',
      symbols: 'amend_daily_review',
      visibility: 'pub(crate)',
    }),
    'daily review writes root should re-export amend_daily_review from amend.rs',
  );
  assert.match(writesRootSource, /fn validate_review_scales\(/);
  assert.match(writesSource, /pub\(crate\) fn add_daily_review\(/);
  assert.match(writesSource, /pub\(crate\) fn amend_daily_review\(/);
  assert.match(readsSource, /pub\(crate\) fn get_daily_review\(/);
  assert.match(readsSource, /pub\(crate\) fn get_review_history\(/);
});
