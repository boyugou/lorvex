import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, readRustSources, repoRoot } from './shared.mjs';

test('server_guidance is organized as a folder-backed subsystem with guide and task-pattern-analysis modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/guidance/mod.rs'),
    'utf8',
  );
  const guideSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/guidance/guide.rs'),
    'utf8',
  );
  const taskPatternAnalysisRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/guidance/task_pattern_analysis/mod.rs'),
    'utf8',
  );
  const taskPatternAnalysisSource = readRustSources(
    'mcp-server/src/system/guidance/task_pattern_analysis/mod.rs',
    'mcp-server/src/system/guidance/task_pattern_analysis',
  );

  assert.match(rootSource, /^mod guide;$/m);
  assert.match(rootSource, /^mod task_pattern_analysis;$/m);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'guide',
    symbols: 'get_guide',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'task_pattern_analysis',
    symbols: 'analyze_task_patterns',
  }), true);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn get_guide\(|\npub\(crate\) fn analyze_task_patterns\(/,
    'server_guidance root should remain a composition root after folder extraction',
  );

  assert.match(guideSource, /\npub\(crate\) fn get_guide\(/);
  assert.match(taskPatternAnalysisRootSource, /^mod metrics;$/m);
  assert.match(taskPatternAnalysisRootSource, /^mod render;$/m);
  // metrics is now a folder-backed module (`metrics/mod.rs` + tests),
  // render still lives as a flat `render.rs`.
  assert.ok(
    fs.existsSync(path.join(repoRoot, 'mcp-server/src/system/guidance/task_pattern_analysis/metrics/mod.rs')),
    'server_guidance/task_pattern_analysis/metrics/mod.rs should exist',
  );
  assert.ok(
    fs.existsSync(path.join(repoRoot, 'mcp-server/src/system/guidance/task_pattern_analysis/render.rs')),
    'server_guidance/task_pattern_analysis/render.rs should exist',
  );
  assert.match(taskPatternAnalysisSource, /\npub\(crate\) fn analyze_task_patterns\(/);
});
