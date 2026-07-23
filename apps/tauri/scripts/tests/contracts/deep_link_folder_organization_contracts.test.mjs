import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('deep-link runtime is organized as a focused module tree', () => {
  const deepLinkDir = path.join(repoRoot, 'app/src-tauri/src/deep_link');
  const modSource = fs.readFileSync(path.join(deepLinkDir, 'mod.rs'), 'utf8');
  const targetSource = fs.readFileSync(path.join(deepLinkDir, 'target.rs'), 'utf8');
  const parseSource = fs.readFileSync(path.join(deepLinkDir, 'parse.rs'), 'utf8');
  const queueSource = fs.readFileSync(path.join(deepLinkDir, 'queue.rs'), 'utf8');
  const testsSource = fs.readFileSync(path.join(deepLinkDir, 'tests.rs'), 'utf8');

  assert.deepEqual(
    fs
      .readdirSync(deepLinkDir)
      .filter((entry) => entry.endsWith('.rs'))
      .sort(),
    ['mod.rs', 'parse.rs', 'queue.rs', 'target.rs', 'tests.rs'],
    'deep_link/ should expose focused parse, queue, target, and tests modules',
  );

  assert.equal(hasRustUseReexport(modSource, {
    visibility: 'pub',
    modulePath: 'parse',
    symbols: 'parse_opened_url_result',
  }), true);
  assert.equal(hasRustUseReexport(modSource, {
    visibility: 'pub',
    modulePath: 'queue',
    symbols: ['acknowledge_pending_payload', 'enqueue_pending', 'take_pending_payload'],
  }), true);
  assert.equal(hasRustUseReexport(modSource, {
    visibility: 'pub',
    modulePath: 'target',
    symbols: ['DeepLinkTarget', 'DeepLinkTargetPayload'],
  }), true);
  assert.match(modSource, /^pub const DEEP_LINK_OPEN_EVENT: &str = "deep-link:\/\/open";$/m);
  assert.match(modSource, /mod parse;/m);
  assert.match(modSource, /^mod queue;$/m);
  assert.match(modSource, /^mod target;$/m);
  assert.match(modSource, /^#\[cfg\(test\)\]$/m);
  assert.match(modSource, /^mod tests;$/m);
  assert.doesNotMatch(modSource, /\npub fn parse_opened_url_result\(/);
  assert.doesNotMatch(modSource, /\npub fn enqueue_pending\(/);
  assert.doesNotMatch(modSource, /\npub enum DeepLinkTarget \{/);

  assert.match(targetSource, /pub enum DeepLinkTarget \{/);
  assert.match(targetSource, /pub struct DeepLinkTargetPayload \{/);
  assert.match(parseSource, /pub fn parse_opened_url_result\(/);
  assert.match(queueSource, /const MAX_PENDING_DEEP_LINKS: usize = \d+;/);
  assert.match(queueSource, /pub fn enqueue_pending\(/);
  assert.match(queueSource, /pub fn take_pending_payload\(/);
  assert.match(queueSource, /pub fn acknowledge_pending_payload\(/);
  assert.match(testsSource, /fn deep_link_parse_today_route\(/);
  assert.match(testsSource, /fn deep_link_acknowledge_removes_matching_quick_capture_pending_entry\(/);
});
