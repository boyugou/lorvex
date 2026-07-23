import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('server_guidance_support is organized as a folder-backed support subtree', () => {
  const suiteRoot = path.join(repoRoot, 'mcp-server/src/system/guidance_support');
  const rootSource = fs.readFileSync(path.join(suiteRoot, 'mod.rs'), 'utf8');

  for (const fileName of ['guide_render.rs', 'guide_state.rs', 'severity.rs', 'tests.rs']) {
    assert.ok(
      fs.existsSync(path.join(suiteRoot, fileName)),
      `server_guidance_support should include ${fileName}`,
    );
  }

  assert.match(rootSource, /^mod guide_render;$/m);
  assert.match(rootSource, /^mod guide_state;$/m);
  assert.match(rootSource, /^mod severity;$/m);
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'guide_render',
      symbols: ['build_guide', 'guide_topic_to_str'],
      visibility: 'pub(crate)',
    }),
    'server_guidance_support should re-export guide rendering helpers from guide_render.rs',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'guide_state',
      symbols: ['auto_detect_guide_topic', 'guide_suggested_actions', 'GuideState'],
      visibility: 'pub(crate)',
    }),
    'server_guidance_support should re-export guide state helpers from guide_state.rs',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'severity',
      symbols: 'severity_by_count',
      visibility: 'pub(crate)',
    }),
    'server_guidance_support should re-export severity helpers from severity.rs',
  );
});
