#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_TAG = '[verify:desktop-channel]';

function assert(condition, message) {
  if (!condition) {
    throw new Error(`${SCRIPT_TAG} ${message}`);
  }
}

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

export function verifyDesktopChannelContract({ repoRoot = resolveRepoRoot() } = {}) {
  const desktopConfigPath = path.join(repoRoot, 'app', 'src-tauri', 'tauri.conf.json');
  const appPackagePath = path.join(repoRoot, 'app', 'package.json');
  const runtimeResolverPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'mcp_runtime.rs');
  const desktopConfig = JSON.parse(fs.readFileSync(desktopConfigPath, 'utf8'));
  const appPackage = JSON.parse(fs.readFileSync(appPackagePath, 'utf8'));
  const runtimeResolverSource = fs.readFileSync(runtimeResolverPath, 'utf8');

  const beforeBuildCommand = desktopConfig?.build?.beforeBuildCommand;
  const beforeDevCommand = desktopConfig?.build?.beforeDevCommand;
  assert(
    typeof beforeDevCommand === 'string' && beforeDevCommand.length > 0,
    'desktop beforeDevCommand is missing',
  );
  assert(
    /\bprepare:mcp\b/.test(beforeDevCommand),
    'desktop beforeDevCommand must prepare the MCP runtime',
  );
  assert(
    !/prepare:mcp-runtime(?::rust)?/.test(beforeDevCommand),
    'desktop beforeDevCommand must not invoke legacy migration-era MCP prepare commands',
  );

  assert(
    typeof beforeBuildCommand === 'string' && beforeBuildCommand.length > 0,
    'desktop beforeBuildCommand is missing',
  );
  assert(
    /\bprepare:mcp\b/.test(beforeBuildCommand),
    'desktop beforeBuildCommand must prepare the MCP runtime',
  );
  assert(
    !/prepare:mcp-runtime(?::rust)?/.test(beforeBuildCommand),
    'desktop beforeBuildCommand must not invoke legacy migration-era MCP prepare commands',
  );

  const resources = desktopConfig?.bundle?.resources;
  assert(Array.isArray(resources), 'desktop bundle.resources must be an array');
  const resourceSet = new Set(resources);
  assert(
    resourceSet.has('resources/mcp-server'),
    'desktop bundle.resources must include resources/mcp-server',
  );
  assert(
    !resourceSet.has('resources/mcp-runtime'),
    'desktop bundle.resources must not include resources/mcp-runtime',
  );
  assert(
    !resourceSet.has('resources/runtime'),
    'desktop bundle.resources must not include resources/runtime',
  );

  const scripts = appPackage?.scripts ?? {};
  assert(
    Object.hasOwn(scripts, 'prepare:mcp'),
    'app package must expose the canonical prepare:mcp script',
  );
  assert(
    !Object.hasOwn(scripts, 'prepare:mcp-runtime'),
    'app package must not expose legacy prepare:mcp-runtime script',
  );
  assert(
    !Object.hasOwn(scripts, 'prepare:mcp-runtime:rust'),
    'app package must not expose legacy prepare:mcp-runtime:rust script',
  );

  const legacyScriptPaths = [
    path.join(repoRoot, 'scripts', 'prepare_rust_mcp_runtime.mjs'),
    path.join(repoRoot, 'scripts', 'verify_rust_mcp_runtime_bundle.mjs'),
  ];
  for (const legacyPath of legacyScriptPaths) {
    assert(!fs.existsSync(legacyPath), `legacy Node runtime script must be removed: ${legacyPath}`);
  }

  const bannedResolverPatterns = [
    'find_bundled_mcp_runtime',
    'find_node_runtime_binary',
    'mcp-server/src/index.ts',
    'tsx',
  ];
  for (const pattern of bannedResolverPatterns) {
    assert(
      !runtimeResolverSource.includes(pattern),
      `mcp runtime resolver must not include legacy Node/TS fallback pattern: ${pattern}`,
    );
  }

  return { ok: true };
}

function runCli() {
  try {
    verifyDesktopChannelContract();
    console.log(`${SCRIPT_TAG} Desktop runtime channel checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
