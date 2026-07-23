import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { createReleaseManifest } from '../../release/create_manifest.mjs';

function writeFile(targetPath, contents = 'stub') {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, contents, 'utf8');
}

test('createReleaseManifest builds the desktop updater manifest from macOS and Windows artifacts', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-manifest-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'latest.json');

  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_aarch64.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_aarch64.dmg.sig'), 'mac-arm-sig');
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_x64.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_x64.dmg.sig'), 'mac-x64-sig');
  writeFile(path.join(distRoot, 'windows', 'Lorvex_0.1.0_x64-setup.exe'));
  writeFile(path.join(distRoot, 'windows', 'Lorvex_0.1.0_x64-setup.exe.sig'), 'win-sig');

  const { manifest } = createReleaseManifest({
    mode: 'desktop',
    distRoot,
    githubRepository: 'boyugou/ai-native-todo',
    tag: 'v0.1.0',
    outputPath,
    now: new Date('2026-03-05T00:00:00.000Z'),
  });

  const saved = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  assert.equal(saved.version, '0.1.0');
  assert.equal(saved.pub_date, '2026-03-05T00:00:00.000Z');
  assert.equal(saved.platforms['darwin-aarch64'].signature, 'mac-arm-sig');
  assert.equal(saved.platforms['darwin-x86_64'].signature, 'mac-x64-sig');
  assert.equal(saved.platforms['windows-x86_64'].signature, 'win-sig');
  assert.match(saved.platforms['darwin-aarch64'].url, /github\.com\/boyugou\/ai-native-todo\/releases\/download\/v0\.1\.0\/Lorvex_0\.1\.0_aarch64\.dmg$/);
  assert.deepEqual(saved, manifest);
});

test('createReleaseManifest maps one universal macOS dmg to both Darwin updater platforms', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-manifest-universal-macos-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'latest.json');

  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_universal.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_universal.dmg.sig'), 'mac-universal-sig');
  writeFile(path.join(distRoot, 'windows', 'Lorvex_0.1.0_x64-setup.exe'));
  writeFile(path.join(distRoot, 'windows', 'Lorvex_0.1.0_x64-setup.exe.sig'), 'win-sig');

  const { manifest } = createReleaseManifest({
    mode: 'desktop',
    distRoot,
    githubRepository: 'boyugou/ai-native-todo',
    tag: 'v0.1.0',
    outputPath,
    now: new Date('2026-03-05T00:00:00.000Z'),
  });

  const saved = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  assert.equal(saved.platforms['darwin-aarch64'].signature, 'mac-universal-sig');
  assert.equal(saved.platforms['darwin-x86_64'].signature, 'mac-universal-sig');
  assert.equal(saved.platforms['darwin-aarch64'].url, saved.platforms['darwin-x86_64'].url);
  assert.match(saved.platforms['darwin-aarch64'].url, /Lorvex_0\.1\.0_universal\.dmg$/);
  assert.deepEqual(saved, manifest);
});

test('createReleaseManifest discovers nested Linux AppImage artifacts downloaded from release workflow', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-manifest-linux-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'latest.json');

  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_aarch64.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_aarch64.dmg.sig'), 'mac-arm-sig');
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_x64.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_x64.dmg.sig'), 'mac-x64-sig');
  writeFile(path.join(distRoot, 'windows', 'Lorvex_0.1.0_x64-setup.exe'));
  writeFile(path.join(distRoot, 'windows', 'Lorvex_0.1.0_x64-setup.exe.sig'), 'win-sig');
  writeFile(path.join(distRoot, 'linux', 'app', 'src-tauri', 'target', 'release', 'bundle', 'appimage', 'Lorvex_0.1.0_amd64.AppImage'));
  writeFile(path.join(distRoot, 'linux', 'app', 'src-tauri', 'target', 'release', 'bundle', 'appimage', 'Lorvex_0.1.0_amd64.AppImage.sig'), 'linux-sig');

  const { manifest } = createReleaseManifest({
    mode: 'desktop',
    distRoot,
    githubRepository: 'boyugou/ai-native-todo',
    tag: 'v0.1.0',
    outputPath,
    now: new Date('2026-03-05T00:00:00.000Z'),
  });

  const saved = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  assert.equal(saved.platforms['linux-x86_64'].signature, 'linux-sig');
  assert.match(saved.platforms['linux-x86_64'].url, /Lorvex_0\.1\.0_amd64\.AppImage$/);
  assert.doesNotMatch(saved.platforms['linux-x86_64'].url, /app\/src-tauri\/target/);
  assert.deepEqual(saved, manifest);
});

test('createReleaseManifest builds a macOS-only updater manifest and supports fallback platform inference', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-manifest-macos-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'latest-macos.json');

  writeFile(path.join(distRoot, 'macos', 'Lorvex_prerelease.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_prerelease.dmg.sig'), 'mac-prerelease-sig');

  const { manifest } = createReleaseManifest({
    mode: 'macos-only',
    distRoot,
    githubRepository: 'boyugou/ai-native-todo',
    tag: 'mac-v0.1.0',
    outputPath,
    fallbackMacosPlatform: 'darwin-aarch64',
    now: new Date('2026-03-05T01:02:03.000Z'),
  });

  const saved = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  assert.equal(saved.version, '0.1.0');
  assert.equal(saved.pub_date, '2026-03-05T01:02:03.000Z');
  assert.equal(Object.keys(saved.platforms).length, 1);
  assert.equal(saved.platforms['darwin-aarch64'].signature, 'mac-prerelease-sig');
  assert.match(saved.platforms['darwin-aarch64'].url, /github\.com\/boyugou\/ai-native-todo\/releases\/download\/mac-v0\.1\.0\/Lorvex_prerelease\.dmg$/);
  assert.deepEqual(saved, manifest);
});

test('createReleaseManifest fails when a required updater signature is missing', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-manifest-missing-sig-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'latest.json');

  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_aarch64.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_aarch64.dmg.sig'), 'mac-arm-sig');
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_x64.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_0.1.0_x64.dmg.sig'), 'mac-x64-sig');
  writeFile(path.join(distRoot, 'windows', 'Lorvex_0.1.0_x64-setup.exe'));

  assert.throws(
    () => createReleaseManifest({
      mode: 'desktop',
      distRoot,
      githubRepository: 'boyugou/ai-native-todo',
      tag: 'v0.1.0',
      outputPath,
      now: new Date('2026-03-05T00:00:00.000Z'),
    }),
    /Missing updater signature: .*Lorvex_0\.1\.0_x64-setup\.exe\.sig/,
  );
});

test('createReleaseManifest fails when a required updater signature is empty', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-manifest-empty-sig-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'latest-macos.json');

  writeFile(path.join(distRoot, 'macos', 'Lorvex_prerelease.dmg'));
  writeFile(path.join(distRoot, 'macos', 'Lorvex_prerelease.dmg.sig'), '   \n');

  assert.throws(
    () => createReleaseManifest({
      mode: 'macos-only',
      distRoot,
      githubRepository: 'boyugou/ai-native-todo',
      tag: 'mac-v0.1.0',
      outputPath,
      fallbackMacosPlatform: 'darwin-aarch64',
      now: new Date('2026-03-05T01:02:03.000Z'),
    }),
    /Empty updater signature: .*Lorvex_prerelease\.dmg\.sig/,
  );
});
