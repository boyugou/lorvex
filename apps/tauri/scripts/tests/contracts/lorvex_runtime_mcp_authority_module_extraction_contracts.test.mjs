import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

const ROOT = 'lorvex-runtime/src/mcp_authority.rs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('lorvex-runtime MCP authority delegates helper domains to focused modules', () => {
  const rootSource = read(ROOT);
  const modelSource = read('lorvex-runtime/src/mcp_authority/model.rs');
  const classifySource = read('lorvex-runtime/src/mcp_authority/classify.rs');
  const detectSource = read('lorvex-runtime/src/mcp_authority/detect.rs');
  const storeSource = read('lorvex-runtime/src/mcp_authority/store.rs');
  const testsSource = read('lorvex-runtime/src/mcp_authority/tests.rs');

  for (const moduleName of ['classify', 'detect', 'model', 'store']) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `mcp_authority.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(rootSource, /^#\[cfg\(test\)\]\nmod tests;$/m);

  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'classify',
      symbols: ['classify_mcp_host'],
    }),
    'root should preserve classify_mcp_host through a re-export',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'detect',
      symbols: ['detect_cli_installation', 'path_is_executable_binary'],
    }),
    'root should preserve CLI detection helpers through re-exports',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'model',
      symbols: ['McpHostAuthorityKind', 'McpHostKind', 'McpHostWriteOutcome'],
    }),
    'root should preserve public model types through re-exports',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'store',
      symbols: [
        'claim_mcp_host_authority',
        'get_mcp_host_authority',
        'reclaim_app_mcp_host_authority_when_cli_missing',
      ],
    }),
    'root should preserve authority storage functions through re-exports',
  );
  assert.ok(
    rootSource.split('\n').length <= 80,
    'mcp_authority.rs should stay a small composition boundary',
  );
  assert.doesNotMatch(
    rootSource,
    /\npub fn classify_mcp_host\b|\nfn unknown_variant_label\b|\npub fn path_is_executable_binary\b|\npub fn detect_cli_installation\b|\nfn cli_binary_candidates\b|\npub fn claim_mcp_host_authority\b|\npub fn reclaim_app_mcp_host_authority_when_cli_missing\b|\nfn read_mcp_host_authority_record\b|\nmod tests \{/,
    'mcp_authority.rs should not keep extracted helper implementations inline',
  );

  assert.match(modelSource, /\npub enum McpHostAuthorityKind\b/);
  assert.match(modelSource, /\npub enum McpHostKind\b/);
  assert.match(modelSource, /\npub enum McpHostWriteOutcome\b/);
  assert.match(modelSource, /\npub\(super\) fn priority_for_kind_str\b/);
  assert.match(classifySource, /\npub fn classify_mcp_host\b/);
  assert.match(classifySource, /\nfn unknown_variant_label\b/);
  assert.match(detectSource, /\npub fn path_is_executable_binary\b/);
  assert.match(detectSource, /\npub fn detect_cli_installation\b/);
  assert.match(detectSource, /\npub\(super\) fn cli_binary_candidates\b/);
  assert.match(storeSource, /\npub fn claim_mcp_host_authority\b/);
  assert.match(storeSource, /\npub fn reclaim_app_mcp_host_authority_when_cli_missing\b/);
  assert.match(storeSource, /\npub fn get_mcp_host_authority\b/);
  assert.match(storeSource, /\npub\(super\) fn read_mcp_host_authority_record\b/);
  assert.match(testsSource, /\nfn classify_cli_binary\(/);
  assert.match(testsSource, /\nfn same_ms_tie_at_equal_priority_admits_first_write_only\(/);
});
