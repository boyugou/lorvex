import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const generatedAppleRoot = 'app/src-tauri/gen/apple';

function collectStringValues(value, currentPath = []) {
  if (typeof value === 'string') {
    return [{ path: currentPath.join('.'), value }];
  }
  if (!value || typeof value !== 'object') {
    return [];
  }
  return Object.entries(value).flatMap(([key, child]) =>
    collectStringValues(child, [...currentPath, key]),
  );
}

function trackedFilesUnder(relativePath) {
  const output = execFileSync('git', ['ls-files', relativePath], {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();
  return output.length === 0 ? [] : output.split('\n');
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
}

test('tracked MCP runtime metadata does not contain machine-local absolute paths', () => {
  const metadataPaths = trackedFilesUnder('app/src-tauri/resources/mcp-server')
    .filter((relativePath) => relativePath.endsWith('/runtime-metadata.json'));

  for (const relativePath of metadataPaths) {
    const metadata = JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
    for (const entry of collectStringValues(metadata, [relativePath])) {
      assert.equal(
        path.isAbsolute(entry.value),
        false,
        `${entry.path} should be repo-relative, got ${entry.value}`,
      );
    }
  }
});

test('Android disables MCP sidecar resources', () => {
  const appEntrySource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/lib.rs'),
    'utf8',
  );
  assert.match(
    appEntrySource,
    /#\[cfg\(not\(target_os = "android"\)\)\]\s*mod mcp_runtime;/,
    'Android builds must keep the MCP runtime module cfg-gated out',
  );
});

test('desktop MCP runtime resources stay configured outside generated Apple output', () => {
  for (const relativePath of [
    'app/src-tauri/tauri.conf.json',
  ]) {
    const config = readJson(relativePath);
    assert.deepEqual(
      config.bundle.resources,
      ['resources/mcp-server'],
      `${relativePath} must keep the legitimate desktop MCP resource bundle`,
    );
  }
});

test('generated Apple output is not tracked in the Tauri tree', () => {
  assert.equal(
    fs.existsSync(path.join(repoRoot, generatedAppleRoot)),
    false,
    'Tauri must not track generated Apple output; Apple platform output belongs to apps/apple',
  );
});

test('app MCP runtime resolver is metadata-first and rejects bad metadata artifacts', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/mcp_runtime.rs'),
    'utf8',
  );

  assert.match(source, /runtime-metadata\.json/);
  assert.match(source, /find_metadata_declared_mcp_server_binary/);
  assert.match(source, /resolve_runtime_metadata_binary/);
  assert.match(source, /lorvex_runtime::path_is_executable_binary/);
  assert.match(
    source,
    /find_metadata_declared_mcp_server_binary\(repo_root,\s*current_exe\)\?/,
    'metadata lookup errors must stop resolution instead of falling through to heuristic probing',
  );
});
