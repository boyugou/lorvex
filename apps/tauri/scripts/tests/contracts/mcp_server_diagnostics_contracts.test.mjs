import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bwriteln!\s*\(\s*(?:std::io::)?(?:stdout|stderr)\s*\(|\bstd::io::(?:stdout|stderr)\s*\(|\buse\s+std::io::\{[^}]*\b(?:stdout|stderr)\b/;
const DIRECT_OUTPUT_MACRO_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bwriteln!\s*\(\s*(?:std::io::)?(?:stdout|stderr)\s*\(/;

// `server/mod.rs` is the router root; the rest of the server/ subtree hosts
// per-concern siblings (construction, connections, dry_run, diagnostics,
// handler) including `startup.rs` for the startup diagnostic helpers. They
// all belong to the same MCP server core, so the contract reads them together.
const MCP_SERVER_PATHS = [
  'mcp-server/src/server/mod.rs',
  'mcp-server/src/server/construction.rs',
  'mcp-server/src/server/connections.rs',
  'mcp-server/src/server/connections_async.rs',
  'mcp-server/src/server/diagnostics.rs',
  'mcp-server/src/server/dry_run.rs',
  'mcp-server/src/server/handler.rs',
  'mcp-server/src/server/startup.rs',
];
const MCP_STDIO_LIFECYCLE_PATH = 'mcp-server/src/lib.rs';
const MCP_RUNTIME_DIAGNOSTIC_PATHS = [
  'mcp-server/src/runtime/tool_timeout/mod.rs',
  'mcp-server/src/runtime/rate_limit/mod.rs',
  'mcp-server/src/system/handler_support/errors/mod.rs',
  'mcp-server/src/runtime/change_tracking/hlc.rs',
  'mcp-server/src/runtime/change_tracking/log_change.rs',
  'mcp-server/src/shutdown/mod.rs',
];

test('MCP server core diagnostics avoid direct stdout and stderr output', () => {
  const source = MCP_SERVER_PATHS
    .map((relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'))
    .join('\n');

  for (const relativePath of MCP_SERVER_PATHS) {
    const fileSource = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(
      fileSource,
      DIRECT_OUTPUT_PATTERN,
      `${relativePath} must return or persist diagnostics instead of writing direct output`,
    );
  }
  assert.match(source, /record_startup_warning/);
  assert.match(source, /record_startup_info/);
  assert.match(source, /mcp\.startup\.pending_queue_retention_failed/);
  assert.match(source, /mcp\.startup\.trash_purge_deleted/);
  assert.match(source, /mcp\.runtime\.transaction_/);
});

test('MCP stdio lifecycle diagnostics avoid direct stdout and stderr output', () => {
  const source = fs.readFileSync(path.join(repoRoot, MCP_STDIO_LIFECYCLE_PATH), 'utf8');

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_MACRO_PATTERN,
    `${MCP_STDIO_LIFECYCLE_PATH} must emit lifecycle diagnostics through structured tracing`,
  );
  assert.match(source, /tracing::(?:info|warn|error)!\(/);
  assert.match(source, /ParentProcessChanged/);
  assert.match(source, /Signal/);
});

test('MCP runtime diagnostics avoid direct stdout and stderr output', () => {
  for (const sourcePath of MCP_RUNTIME_DIAGNOSTIC_PATHS) {
    const source = fs.readFileSync(path.join(repoRoot, sourcePath), 'utf8');

    assert.doesNotMatch(
      source,
      DIRECT_OUTPUT_MACRO_PATTERN,
      `${sourcePath} must emit runtime diagnostics through structured tracing`,
    );
  }
});
