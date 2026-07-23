#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(message) {
  throw new Error(`[verify_mcp_runtime_bundle] ${message}`);
}

function ensureExecutableBinary(targetPath, label) {
  if (!fs.existsSync(targetPath) || !fs.statSync(targetPath).isFile()) {
    fail(
      `${label} missing: ${targetPath}. Run \`npm -w app run prepare:mcp -- --debug\` before verify:mcp-runtime-bundle.`,
    );
  }
  const stat = fs.statSync(targetPath);
  if (stat.size === 0) {
    fail(`${label} is empty: ${targetPath}`);
  }
  if (process.platform !== 'win32' && (stat.mode & 0o111) === 0) {
    fail(`${label} is not executable: ${targetPath}`);
  }
}

function ensureFile(targetPath, label) {
  if (!fs.existsSync(targetPath) || !fs.statSync(targetPath).isFile()) {
    fail(`${label} missing: ${targetPath}`);
  }
}

function ensureMissing(targetPath, label) {
  if (fs.existsSync(targetPath)) {
    fail(`legacy runtime artifact still present (${label}): ${targetPath}`);
  }
}

function assertNoAbsoluteMetadataPaths(value, pathSegments = []) {
  if (typeof value === 'string') {
    if (path.isAbsolute(value)) {
      fail(`runtime metadata contains absolute path at ${pathSegments.join('.')}: ${value}`);
    }
    return;
  }
  if (!value || typeof value !== 'object') {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    assertNoAbsoluteMetadataPaths(child, [...pathSegments, key]);
  }
}

function readRuntimeMetadata(metadataPath) {
  ensureFile(metadataPath, 'Runtime metadata');
  const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
  assertNoAbsoluteMetadataPaths(metadata, ['runtime-metadata.json']);
  const standalone = metadata?.installed?.standalone;
  const bundleResource = metadata?.installed?.bundle_resource;
  if (typeof standalone !== 'string' || standalone.length === 0) {
    fail('runtime metadata missing installed.standalone');
  }
  if (typeof bundleResource !== 'string' || bundleResource.length === 0) {
    fail('runtime metadata missing installed.bundle_resource');
  }
  return { standalone, bundleResource };
}

function toPortableRelativePath(root, targetPath) {
  return path.relative(root, targetPath).split(path.sep).join('/');
}

function resourceRelativePath(repoRelativePath) {
  const parts = repoRelativePath.split(/[\\/]+/);
  const resourcesIndex = parts.lastIndexOf('resources');
  return resourcesIndex >= 0
    ? parts.slice(resourcesIndex + 1).join('/')
    : repoRelativePath;
}

function pathsMatchByRepoOrResourceRelative(actual, expected) {
  if (actual === expected) {
    return true;
  }
  return expected.includes('/gen/apple/assets/resources/')
    && resourceRelativePath(actual) === resourceRelativePath(expected);
}

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

export function verifyMcpRuntimeBundle({
  repoRoot = resolveRepoRoot(),
  bundleDir = path.join(repoRoot, 'app', 'src-tauri', 'resources', 'mcp-server'),
  standaloneDir = path.join(repoRoot, 'mcp-server', 'bin'),
  resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources'),
  exeExt = process.platform === 'win32' ? '.exe' : '',
} = {}) {
  const binaryName = `lorvex-mcp-server${exeExt}`;
  ensureExecutableBinary(path.join(bundleDir, binaryName), 'Bundled Rust MCP server binary');
  ensureExecutableBinary(path.join(standaloneDir, binaryName), 'Standalone Rust MCP server binary');

  const legacyPaths = [
    { path: path.join(resourcesRoot, 'mcp-runtime'), label: 'legacy mcp-runtime directory' },
    { path: path.join(resourcesRoot, 'runtime'), label: 'legacy runtime directory' },
  ];
  for (const legacyPath of legacyPaths) {
    ensureMissing(legacyPath.path, legacyPath.label);
  }

  const metadataPath = path.join(bundleDir, 'runtime-metadata.json');
  const metadata = readRuntimeMetadata(metadataPath);
  const expectedBundleResource = toPortableRelativePath(repoRoot, path.join(bundleDir, binaryName));
  const expectedStandalone = toPortableRelativePath(repoRoot, path.join(standaloneDir, binaryName));
  if (!pathsMatchByRepoOrResourceRelative(metadata.bundleResource, expectedBundleResource)) {
    fail(
      `runtime metadata installed.bundle_resource must point at bundled binary: expected ${expectedBundleResource}, got ${metadata.bundleResource}`,
    );
  }
  if (metadata.standalone !== expectedStandalone) {
    fail(
      `runtime metadata installed.standalone must point at standalone binary: expected ${expectedStandalone}, got ${metadata.standalone}`,
    );
  }

  console.log('[verify_mcp_runtime_bundle] OK');
  console.log(`  bundle: ${path.join(bundleDir, binaryName)}`);
  console.log(`  standalone: ${path.join(standaloneDir, binaryName)}`);
}

const repoRoot = resolveRepoRoot();
const bundleArgIndex = process.argv.indexOf('--bundle-dir');
const standaloneArgIndex = process.argv.indexOf('--standalone-dir');

if (bundleArgIndex >= 0 && !process.argv[bundleArgIndex + 1]) {
  fail('`--bundle-dir` provided without a value');
}

if (standaloneArgIndex >= 0 && !process.argv[standaloneArgIndex + 1]) {
  fail('`--standalone-dir` provided without a value');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  verifyMcpRuntimeBundle({
    repoRoot,
    bundleDir: bundleArgIndex >= 0
      ? path.resolve(process.argv[bundleArgIndex + 1] ?? '')
      : path.join(repoRoot, 'app', 'src-tauri', 'resources', 'mcp-server'),
    standaloneDir: standaloneArgIndex >= 0
      ? path.resolve(process.argv[standaloneArgIndex + 1] ?? '')
      : path.join(repoRoot, 'mcp-server', 'bin'),
  });
}
