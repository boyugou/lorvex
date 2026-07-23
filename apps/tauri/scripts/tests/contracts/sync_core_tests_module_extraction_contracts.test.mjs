import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('lorvex-sync pending inbox and outbox enqueue keep large tests in sibling modules', () => {
  for (const moduleName of ['pending_inbox', 'outbox_enqueue']) {
    const flatRootPath = path.join(repoRoot, `lorvex-sync/src/${moduleName}.rs`);
    const folderRootPath = path.join(repoRoot, `lorvex-sync/src/${moduleName}/mod.rs`);
    const rootPath = fs.existsSync(folderRootPath) ? folderRootPath : flatRootPath;
    const flatTestsPath = path.join(repoRoot, `lorvex-sync/src/${moduleName}/tests.rs`);
    const folderTestsPath = path.join(repoRoot, `lorvex-sync/src/${moduleName}/tests/mod.rs`);
    const testsPath = fs.existsSync(folderTestsPath) ? folderTestsPath : flatTestsPath;
    const rootSource = fs.readFileSync(rootPath, 'utf8');
    const testsSource = fs.readFileSync(testsPath, 'utf8');

    assert.match(
      rootSource,
      /#\[cfg\(test\)\]\s*mod tests;/,
      `${moduleName}.rs should register tests through a sibling tests module`,
    );
    assert.doesNotMatch(
      rootSource,
      /#\[cfg\(test\)\]\s*mod tests\s*\{/,
      `${moduleName}.rs should not inline the large test module`,
    );
    if (testsPath === flatTestsPath) {
      assert.match(
        testsSource,
        /use super::\*/m,
        `${moduleName}/tests.rs should keep private implementation coverage colocated with the module`,
      );
    } else {
      assert.match(
        testsSource,
        /^mod [a-z_]+;$/m,
        `${moduleName}/tests/mod.rs should register focused private test modules`,
      );
      const childSources = fs
        .readdirSync(path.dirname(folderTestsPath))
        .filter((entry) => entry.endsWith('.rs') && entry !== 'mod.rs')
        .map((entry) => ({
          entry,
          source: fs.readFileSync(path.join(path.dirname(folderTestsPath), entry), 'utf8'),
        }));
      const supportSource = childSources.find(({ entry }) => entry === 'support.rs')?.source ?? '';
      assert.ok(
        /use super::super::\*/m.test(supportSource)
          || /pub\(super\) use super::super::\{[\s\S]*enqueue_entity_upsert[\s\S]*enqueue_payload_upsert[\s\S]*OutboxWriteContext[\s\S]*\};/.test(supportSource),
        `${moduleName}/tests/support.rs should re-export private implementation helpers for focused behavior modules`,
      );
      const behaviorModules = childSources.filter(({ source }) => /^#\[test\]/m.test(source));
      assert.ok(
        behaviorModules.length > 0,
        `${moduleName}/tests/*.rs should contain focused behavior test modules`,
      );
      for (const { entry, source } of behaviorModules) {
        assert.match(
          source,
          /use super::super::\*|use super::support::(?:\*|\{)/m,
          `${moduleName}/tests/${entry} should keep private implementation coverage directly or through the support module`,
        );
      }
    }
  }
});
