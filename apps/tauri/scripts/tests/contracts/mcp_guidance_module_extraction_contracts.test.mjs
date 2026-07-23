import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, readRustSources, repoRoot } from './shared.mjs';

test('mcp guidance state and rendering helpers live in a dedicated module instead of server_handler_support', () => {
  const guidanceSupportPath = path.join(repoRoot, 'mcp-server/src/system/guidance_support/mod.rs');
  const helpersSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/system/handler_support.rs'), 'utf8');
  const guidanceRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/guidance/mod.rs'),
    'utf8',
  );
  const guidanceSource = readRustSources(
    'mcp-server/src/system/guidance/mod.rs',
    'mcp-server/src/system/guidance/guide.rs',
    'mcp-server/src/system/guidance/task_pattern_analysis/mod.rs',
    'mcp-server/src/system/guidance/task_pattern_analysis',
  );

  assert.ok(
    fs.existsSync(guidanceSupportPath),
    'server_guidance_support/mod.rs should exist as the dedicated home for guide state/render helpers',
  );

  const guidanceSupportSource = readRustSources(
    'mcp-server/src/system/guidance_support/mod.rs',
    'mcp-server/src/system/guidance_support',
  );

  for (const snippet of [
    'struct GuideState',
    'fn guide_topic_to_str(',
    'fn auto_detect_guide_topic(',
    'fn guide_suggested_actions(',
    'fn build_guide(',
    'fn severity_by_count(',
  ]) {
    assert.doesNotMatch(
      helpersSource,
      new RegExp(snippet.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `server_handler_support.rs should not keep guidance helper ${snippet}`,
    );
  }

  assert.match(
    guidanceSupportSource,
    /pub\(crate\)\s+struct GuideState[\s\S]*pub\(crate\)\s+(?:const )?fn severity_by_count\(/,
    'server_guidance_support module tree should own GuideState, topic routing, rendering, and severity helpers',
  );
  assert.ok(
    hasRustUseReexport(guidanceRootSource, {
      modulePath: 'guide',
      symbols: 'get_guide',
      visibility: 'pub(crate)',
    }) && hasRustUseReexport(guidanceRootSource, {
      modulePath: 'task_pattern_analysis',
      symbols: 'analyze_task_patterns',
      visibility: 'pub(crate)',
    }),
    'server_guidance.rs should remain a composition root that re-exports dedicated guidance entrypoints',
  );
  assert.match(
    guidanceSource,
    /use crate::system::guidance_support::\{[\s\S]*GuideState[\s\S]*build_guide[\s\S]*}/,
    'server_guidance should import guide-state rendering helpers from the dedicated support module',
  );
  assert.match(
    guidanceSource,
    /use crate::system::guidance_support::severity_by_count;/,
    'server_guidance should import learning-insight severity helpers from the dedicated support module',
  );
});
