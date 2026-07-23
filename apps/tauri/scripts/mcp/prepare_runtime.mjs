#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: 'inherit',
    ...options,
  });
  if (result.error) {
    throw result.error;
  }
  if (typeof result.status === 'number' && result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed with exit code ${result.status}`);
  }
}

function ensureFile(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw new Error(`${label} not found: ${filePath}`);
  }
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function cleanGeneratedDir(dirPath) {
  ensureDir(dirPath);
  for (const entry of fs.readdirSync(dirPath)) {
    if (entry === '.gitkeep') {
      continue;
    }
    fs.rmSync(path.join(dirPath, entry), { recursive: true, force: true });
  }
}

function repoRelativePath(repoRoot, targetPath) {
  const relativePath = path.relative(repoRoot, targetPath);
  if (!relativePath || relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
    throw new Error(`Runtime metadata path must stay under repo root: ${targetPath}`);
  }
  return relativePath.split(path.sep).join('/');
}

export function buildRuntimeMetadata({
  repoRoot = resolveRepoRoot(),
  profile,
  binarySource,
  standaloneDest,
  bundleDest,
  generatedAt = new Date(),
}) {
  return {
    generated_at: generatedAt.toISOString(),
    profile,
    source_binary: repoRelativePath(repoRoot, binarySource),
    installed: {
      standalone: repoRelativePath(repoRoot, standaloneDest),
      bundle_resource: repoRelativePath(repoRoot, bundleDest),
    },
  };
}

export function removeLegacyRuntimeArtifacts({
  repoRoot = resolveRepoRoot(),
} = {}) {
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const bundleResourceDir = path.join(resourcesRoot, 'mcp-server');
  const devStandaloneDir = path.join(repoRoot, 'mcp-server', 'bin');
  const legacyPaths = [
    path.join(resourcesRoot, 'mcp-runtime'),
    path.join(resourcesRoot, 'runtime'),
  ];

  cleanGeneratedDir(bundleResourceDir);
  cleanGeneratedDir(devStandaloneDir);

  for (const legacyPath of legacyPaths) {
    fs.rmSync(legacyPath, { recursive: true, force: true });
  }
}

export function prepareMcpRuntime({
  repoRoot = resolveRepoRoot(),
  debugMode = process.argv.includes('--debug'),
  platform = process.platform,
} = {}) {
  const isMac = platform === 'darwin';
  const isWindows = platform === 'win32';
  const exeExt = isWindows ? '.exe' : '';
  const profile = debugMode ? 'debug' : 'release';
  const universal = isMac && !debugMode; // Build universal binary for macOS release builds

  // `mcp-server` is a workspace member (see top-level Cargo.toml), so
  // `cargo build --manifest-path mcp-server/Cargo.toml` from the
  // workspace root writes the binary into the WORKSPACE target dir
  // (`<repo>/target/profile/...`), NOT the per-crate subdir
  // (`mcp-server/target/profile/...`). Pre-fix the script always
  // looked in `mcp-server/target/profile/` and reported "Rust MCP
  // server binary not found" for the non-universal debug path —
  // `prepare:mcp -- --debug` was completely broken on Linux despite
  // the cargo build itself succeeding silently. The macOS universal
  // path still works because `lipo` writes to that location
  // explicitly. `binarySource` is now resolved per branch so the
  // path always matches where cargo (or lipo) actually emitted the
  // artifact.
  let binarySource;
  if (universal) {
    // Build for both architectures and combine with lipo.
    // Audit #2312: `--locked` on both arch builds so a stale
    // registry cache can't silently pull newer patch versions
    // than what the repo ships. Both arches must resolve from
    // the same Cargo.lock or the universal binary is no longer
    // a reproducible artifact.
    console.log(`[prepare_mcp_runtime] Building MCP runtime (${profile}, universal)...`);
    for (const target of ['aarch64-apple-darwin', 'x86_64-apple-darwin']) {
      const args = ['build', '--manifest-path', path.join(repoRoot, 'mcp-server', 'Cargo.toml'), '--release', '--locked', '--target', target];
      runCommand('cargo', args, { cwd: repoRoot });
    }
    const armBin = path.join(repoRoot, 'target', 'aarch64-apple-darwin', profile, 'lorvex-mcp-server');
    const x64Bin = path.join(repoRoot, 'target', 'x86_64-apple-darwin', profile, 'lorvex-mcp-server');
    ensureFile(armBin, 'MCP server aarch64 binary');
    ensureFile(x64Bin, 'MCP server x86_64 binary');
    // Combine into universal binary at `mcp-server/target/profile/`
    // (a non-cargo path created by lipo for the explicit purpose of
    // staging the universal artifact).
    const universalBin = path.join(repoRoot, 'mcp-server', 'target', profile, 'lorvex-mcp-server');
    fs.mkdirSync(path.dirname(universalBin), { recursive: true });
    runCommand('lipo', ['-create', '-output', universalBin, armBin, x64Bin], { cwd: repoRoot });
    console.log(`[prepare_mcp_runtime] Created universal MCP binary via lipo`);
    binarySource = universalBin;
  } else {
    // Audit #2312: `--locked` for release; debug builds stay
    // flexible so developer test iterations don't trip on a
    // deliberately-modified Cargo.lock.
    const cargoArgs = ['build', '--manifest-path', path.join(repoRoot, 'mcp-server', 'Cargo.toml')];
    if (!debugMode) {
      cargoArgs.push('--release', '--locked');
    }
    console.log(`[prepare_mcp_runtime] Building MCP runtime (${profile})...`);
    runCommand('cargo', cargoArgs, { cwd: repoRoot });
    // Workspace target dir — see comment above.
    binarySource = path.join(repoRoot, 'target', profile, `lorvex-mcp-server${exeExt}`);
  }
  ensureFile(binarySource, 'Rust MCP server binary');

  removeLegacyRuntimeArtifacts({ repoRoot, exeExt });

  const devStandaloneDir = path.join(repoRoot, 'mcp-server', 'bin');
  const bundleResourceDir = path.join(repoRoot, 'app', 'src-tauri', 'resources', 'mcp-server');
  const standaloneDest = path.join(devStandaloneDir, `lorvex-mcp-server${exeExt}`);
  const bundleDest = path.join(bundleResourceDir, `lorvex-mcp-server${exeExt}`);

  fs.copyFileSync(binarySource, standaloneDest);
  fs.copyFileSync(binarySource, bundleDest);

  if (!isWindows) {
    fs.chmodSync(standaloneDest, 0o755);
    fs.chmodSync(bundleDest, 0o755);
  }

  // Sign the bundled MCP binary for notarization (macOS only, release builds).
  // Uses APPLE_SIGNING_IDENTITY env var, or falls back to reading signingIdentity
  // from tauri.conf.json so the MCP binary matches the app's signing identity.
  if (platform === 'darwin' && !debugMode) {
    let signingIdentity = process.env.APPLE_SIGNING_IDENTITY;
    if (!signingIdentity) {
      try {
        const tauriConfPath = path.join(repoRoot, 'app', 'src-tauri', 'tauri.conf.json');
        const tauriConf = JSON.parse(fs.readFileSync(tauriConfPath, 'utf8'));
        signingIdentity = tauriConf?.bundle?.macOS?.signingIdentity;
      } catch { /* ignore */ }
    }
    if (signingIdentity) {
      console.log('[prepare_mcp_runtime] Signing MCP binary for notarization...');
      runCommand('codesign', [
        '--force', '--options', 'runtime', '--timestamp',
        '--sign', signingIdentity,
        bundleDest,
      ]);
    }
  }

  const metadata = buildRuntimeMetadata({
    repoRoot,
    profile,
    binarySource,
    standaloneDest,
    bundleDest,
  });

  const metadataPath = path.join(bundleResourceDir, 'runtime-metadata.json');
  fs.writeFileSync(metadataPath, JSON.stringify(metadata, null, 2), 'utf8');

  console.log('[prepare_mcp_runtime] Installed MCP runtime.');
  console.log(`  standalone: ${standaloneDest}`);
  console.log(`  resource:   ${bundleDest}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  prepareMcpRuntime();
}
