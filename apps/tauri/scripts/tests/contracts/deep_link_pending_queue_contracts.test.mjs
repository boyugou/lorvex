import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readAppSources, readRustSources } from './shared.mjs';

test('App deep-link drain does not hardcode a pending queue length separate from the Rust runtime', () => {
  const rustSource = readRustSources('app/src-tauri/src/deep_link');
  const appSource = readAppSources();

  assert.match(
    rustSource,
    /const MAX_PENDING_DEEP_LINKS: usize = \d+;/,
    'Rust deep-link runtime should keep an explicit pending queue bound',
  );
  assert.match(
    appSource,
    /const drainPendingDeepLinks = async \(\) => \{[\s\S]*?consumePendingDeepLink\(\);/s,
    'App should keep an explicit pending deep-link drain helper',
  );
  assert.doesNotMatch(
    appSource,
    /for \(let i = 0; i < \d+; i \+= 1\) \{\s*const pending = await consumePendingDeepLink\(\);/s,
    'App should not hardcode a fixed pending deep-link drain count that can drift from the Rust queue contract',
  );
});
