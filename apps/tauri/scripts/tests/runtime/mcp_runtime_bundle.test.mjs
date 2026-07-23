import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { buildRuntimeMetadata, removeLegacyRuntimeArtifacts } from '../../mcp/prepare_runtime.mjs';
import { verifyMcpRuntimeBundle } from '../../mcp/verify_runtime_bundle.mjs';

function writeFile(targetPath, contents = 'stub') {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, contents, 'utf8');
}

function writeExecutable(targetPath, contents = '#!/bin/sh\nexit 0\n') {
  writeFile(targetPath, contents);
  if (process.platform !== 'win32') {
    fs.chmodSync(targetPath, 0o755);
  }
}

function makeTempRepoRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-mcp-runtime-'));
}

test('removeLegacyRuntimeArtifacts prunes legacy runtime directories', () => {
  const repoRoot = makeTempRepoRoot();
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const bundleDir = path.join(resourcesRoot, 'mcp-server');
  const standaloneDir = path.join(repoRoot, 'mcp-server', 'bin');

  writeFile(path.join(bundleDir, '.gitkeep'), '');
  writeExecutable(path.join(bundleDir, 'lorvex-mcp-server'));
  writeFile(path.join(standaloneDir, '.gitkeep'), '');
  writeExecutable(path.join(standaloneDir, 'lorvex-mcp-server'));
  writeFile(path.join(resourcesRoot, 'mcp-runtime', 'package.json'), '{}');
  writeFile(path.join(resourcesRoot, 'runtime', 'node'), 'node');

  removeLegacyRuntimeArtifacts({ repoRoot, exeExt: '' });

  assert.deepEqual(fs.readdirSync(bundleDir).sort(), ['.gitkeep']);
  assert.deepEqual(fs.readdirSync(standaloneDir).sort(), ['.gitkeep']);
  assert.equal(fs.existsSync(path.join(resourcesRoot, 'mcp-runtime')), false);
  assert.equal(fs.existsSync(path.join(resourcesRoot, 'runtime')), false);
});

test('verifyMcpRuntimeBundle rejects legacy runtime directory residue', () => {
  const repoRoot = makeTempRepoRoot();
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const bundleDir = path.join(resourcesRoot, 'mcp-server');
  const standaloneDir = path.join(repoRoot, 'mcp-server', 'bin');

  writeExecutable(path.join(bundleDir, 'lorvex-mcp-server'));
  writeExecutable(path.join(standaloneDir, 'lorvex-mcp-server'));
  writeFile(
    path.join(bundleDir, 'runtime-metadata.json'),
    JSON.stringify({
      installed: {
        standalone: 'mcp-server/bin/lorvex-mcp-server',
        bundle_resource: 'app/src-tauri/resources/mcp-server/lorvex-mcp-server',
      },
    }),
  );
  writeFile(path.join(resourcesRoot, 'mcp-runtime', 'package.json'), '{}');

  assert.throws(
    () => verifyMcpRuntimeBundle({ repoRoot, bundleDir, standaloneDir, resourcesRoot, exeExt: '' }),
    /legacy runtime artifact/i,
  );
});

test('buildRuntimeMetadata stores repo-relative paths only', () => {
  const repoRoot = makeTempRepoRoot();
  const generatedAt = new Date('2026-04-30T00:00:00.000Z');
  const metadata = buildRuntimeMetadata({
    repoRoot,
    profile: 'release',
    binarySource: path.join(repoRoot, 'mcp-server', 'target', 'release', 'lorvex-mcp-server'),
    standaloneDest: path.join(repoRoot, 'mcp-server', 'bin', 'lorvex-mcp-server'),
    bundleDest: path.join(
      repoRoot,
      'app',
      'src-tauri',
      'resources',
      'mcp-server',
      'lorvex-mcp-server',
    ),
    generatedAt,
  });

  assert.deepEqual(metadata, {
    generated_at: '2026-04-30T00:00:00.000Z',
    profile: 'release',
    source_binary: 'mcp-server/target/release/lorvex-mcp-server',
    installed: {
      standalone: 'mcp-server/bin/lorvex-mcp-server',
      bundle_resource: 'app/src-tauri/resources/mcp-server/lorvex-mcp-server',
    },
  });
});

test('verifyMcpRuntimeBundle rejects absolute paths in metadata', () => {
  const repoRoot = makeTempRepoRoot();
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const bundleDir = path.join(resourcesRoot, 'mcp-server');
  const standaloneDir = path.join(repoRoot, 'mcp-server', 'bin');

  writeExecutable(path.join(bundleDir, 'lorvex-mcp-server'));
  writeExecutable(path.join(standaloneDir, 'lorvex-mcp-server'));
  writeFile(
    path.join(bundleDir, 'runtime-metadata.json'),
    JSON.stringify({
      generated_at: '2026-04-30T00:00:00.000Z',
      profile: 'release',
      source_binary: path.join(repoRoot, 'target', 'release', 'lorvex-mcp-server'),
    }),
  );

  assert.throws(
    () => verifyMcpRuntimeBundle({ repoRoot, bundleDir, standaloneDir, resourcesRoot, exeExt: '' }),
    /absolute path/i,
  );
});

test('verifyMcpRuntimeBundle requires metadata to point at verified artifacts', () => {
  const repoRoot = makeTempRepoRoot();
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const bundleDir = path.join(resourcesRoot, 'mcp-server');
  const standaloneDir = path.join(repoRoot, 'mcp-server', 'bin');

  writeExecutable(path.join(bundleDir, 'lorvex-mcp-server'));
  writeExecutable(path.join(standaloneDir, 'lorvex-mcp-server'));

  assert.throws(
    () => verifyMcpRuntimeBundle({ repoRoot, bundleDir, standaloneDir, resourcesRoot, exeExt: '' }),
    /Runtime metadata missing/i,
  );

  writeFile(
    path.join(bundleDir, 'runtime-metadata.json'),
    JSON.stringify({
      installed: {
        standalone: 'mcp-server/bin/other',
        bundle_resource: 'app/src-tauri/resources/mcp-server/lorvex-mcp-server',
      },
    }),
  );
  assert.throws(
    () => verifyMcpRuntimeBundle({ repoRoot, bundleDir, standaloneDir, resourcesRoot, exeExt: '' }),
    /installed\.standalone must point at standalone binary/i,
  );
});

test('verifyMcpRuntimeBundle rejects empty or non-executable artifacts', () => {
  const repoRoot = makeTempRepoRoot();
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const bundleDir = path.join(resourcesRoot, 'mcp-server');
  const standaloneDir = path.join(repoRoot, 'mcp-server', 'bin');

  writeExecutable(path.join(standaloneDir, 'lorvex-mcp-server'));
  writeFile(path.join(bundleDir, 'lorvex-mcp-server'), '');
  writeFile(
    path.join(bundleDir, 'runtime-metadata.json'),
    JSON.stringify({
      installed: {
        standalone: 'mcp-server/bin/lorvex-mcp-server',
        bundle_resource: 'app/src-tauri/resources/mcp-server/lorvex-mcp-server',
      },
    }),
  );

  assert.throws(
    () => verifyMcpRuntimeBundle({ repoRoot, bundleDir, standaloneDir, resourcesRoot, exeExt: '' }),
    /Bundled Rust MCP server binary is empty/i,
  );

  writeFile(path.join(bundleDir, 'lorvex-mcp-server'), '#!/bin/sh\nexit 0\n');
  if (process.platform !== 'win32') {
    assert.throws(
      () => verifyMcpRuntimeBundle({ repoRoot, bundleDir, standaloneDir, resourcesRoot, exeExt: '' }),
      /Bundled Rust MCP server binary is not executable/i,
    );
  }
});

test('verifyMcpRuntimeBundle accepts generated bundle metadata by resource-relative target', () => {
  const repoRoot = makeTempRepoRoot();
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const generatedBundleDir = path.join(
    repoRoot,
    'app',
    'src-tauri',
    'gen',
    'apple',
    'assets',
    'resources',
    'mcp-server',
  );
  const standaloneDir = path.join(repoRoot, 'mcp-server', 'bin');

  writeExecutable(path.join(generatedBundleDir, 'lorvex-mcp-server'));
  writeExecutable(path.join(standaloneDir, 'lorvex-mcp-server'));
  writeFile(
    path.join(generatedBundleDir, 'runtime-metadata.json'),
    JSON.stringify({
      installed: {
        standalone: 'mcp-server/bin/lorvex-mcp-server',
        bundle_resource: 'app/src-tauri/resources/mcp-server/lorvex-mcp-server',
      },
    }),
  );

  assert.doesNotThrow(() =>
    verifyMcpRuntimeBundle({
      repoRoot,
      bundleDir: generatedBundleDir,
      standaloneDir,
      resourcesRoot,
      exeExt: '',
    }),
  );

  writeFile(
    path.join(generatedBundleDir, 'runtime-metadata.json'),
    JSON.stringify({
      installed: {
        standalone: 'mcp-server/bin/lorvex-mcp-server',
        bundle_resource: 'app/src-tauri/resources/other/lorvex-mcp-server',
      },
    }),
  );
  assert.throws(
    () => verifyMcpRuntimeBundle({
      repoRoot,
      bundleDir: generatedBundleDir,
      standaloneDir,
      resourcesRoot,
      exeExt: '',
    }),
    /installed\.bundle_resource must point at bundled binary/i,
  );
});

test('verifyMcpRuntimeBundle requires exact source bundle metadata path', () => {
  const repoRoot = makeTempRepoRoot();
  const resourcesRoot = path.join(repoRoot, 'app', 'src-tauri', 'resources');
  const bundleDir = path.join(resourcesRoot, 'mcp-server');
  const standaloneDir = path.join(repoRoot, 'mcp-server', 'bin');

  writeExecutable(path.join(bundleDir, 'lorvex-mcp-server'));
  writeExecutable(path.join(standaloneDir, 'lorvex-mcp-server'));
  writeFile(
    path.join(bundleDir, 'runtime-metadata.json'),
    JSON.stringify({
      installed: {
        standalone: 'mcp-server/bin/lorvex-mcp-server',
        bundle_resource: 'app/src-tauri/gen/apple/assets/resources/mcp-server/lorvex-mcp-server',
      },
    }),
  );

  assert.throws(
    () => verifyMcpRuntimeBundle({ repoRoot, bundleDir, standaloneDir, resourcesRoot, exeExt: '' }),
    /installed\.bundle_resource must point at bundled binary/i,
  );
});
