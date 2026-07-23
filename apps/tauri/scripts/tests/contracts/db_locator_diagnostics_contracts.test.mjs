import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bwriteln!\s*\(\s*(?:std::io::)?(?:stdout|stderr)\s*\(|\bstd::io::(?:stdout|stderr)\s*\(|\buse\s+std::io::\{[^}]*\b(?:stdout|stderr)\b/;

const DB_LOCATOR_DIR = 'lorvex-runtime/src/db_locator';
const STORE_CONNECTION_PATH = 'lorvex-store/src/connection/mod.rs';
const APP_CONNECTION_PATH = 'app/src-tauri/src/db/connection.rs';
// After the server.rs → server/ split, the diagnostic-flush call lives in the
// construction sibling that owns `LorvexHandler::new`.
const MCP_SERVER_PATH = 'mcp-server/src/server/construction.rs';
const CLI_STARTUP_PATH = 'lorvex-cli/src/startup_maintenance/mod.rs';

function readAllRustFilesUnder(relativeDir) {
  const absoluteDir = path.join(repoRoot, relativeDir);
  const sources = {};
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile() && entry.name.endsWith('.rs')) {
        const rel = path.relative(repoRoot, full);
        sources[rel] = fs.readFileSync(full, 'utf8');
      }
    }
  }
  walk(absoluteDir);
  return sources;
}

test('db locator returns diagnostics structurally instead of writing direct output', () => {
  const locatorSources = readAllRustFilesUnder(DB_LOCATOR_DIR);
  const connectionSource = fs.readFileSync(path.join(repoRoot, STORE_CONNECTION_PATH), 'utf8');
  const appConnectionSource = fs.readFileSync(path.join(repoRoot, APP_CONNECTION_PATH), 'utf8');
  const mcpServerSource = fs.readFileSync(path.join(repoRoot, MCP_SERVER_PATH), 'utf8');
  const cliStartupSource = fs.readFileSync(path.join(repoRoot, CLI_STARTUP_PATH), 'utf8');

  // The locator (post-split) is a folder of per-concern siblings — none of
  // them may write directly to stdout/stderr. Tests files are scoped under
  // #[cfg(test)] and exempt from this rule.
  for (const [relPath, source] of Object.entries(locatorSources)) {
    if (relPath.endsWith('/tests.rs') || relPath.endsWith('tests.rs')) continue;
    assert.doesNotMatch(
      source,
      DIRECT_OUTPUT_PATTERN,
      `${relPath} must return structured diagnostics instead of writing direct output`,
    );
  }

  // Combine non-test sources for the structural-contract checks. The split
  // moves the `DbLocationDiagnostic` type into types.rs, the queued-state
  // `Vec<DbLocationDiagnostic>` into diagnostics_queue.rs, and the
  // `take_db_location_diagnostics` re-export onto mod.rs — the union must
  // still expose all three.
  const combinedLocator = Object.entries(locatorSources)
    .filter(([rel]) => !rel.endsWith('tests.rs'))
    .map(([, source]) => source)
    .join('\n');

  assert.match(combinedLocator, /DbLocationDiagnostic/);
  assert.match(combinedLocator, /diagnostics:\s*Vec<DbLocationDiagnostic>/);
  assert.match(combinedLocator, /take_db_location_diagnostics/);
  assert.match(connectionSource, /persist_db_location_diagnostics/);
  assert.match(connectionSource, /persist_pending_db_location_diagnostics/);
  assert.match(connectionSource, /store\.db_locator/);
  assert.match(appConnectionSource, /persist_pending_db_location_diagnostics/);
  assert.match(mcpServerSource, /persist_pending_db_location_diagnostics/);
  assert.match(cliStartupSource, /persist_pending_db_location_diagnostics/);
});
