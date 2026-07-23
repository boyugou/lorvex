import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { createReleaseChecksums } from '../../release/write_checksums.mjs';

function writeFile(targetPath, contents = 'stub') {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, contents, 'utf8');
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

test('createReleaseChecksums writes sorted SHA256SUMS entries relative to the release root', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-checksums-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'SHA256SUMS');

  writeFile(path.join(distRoot, 'windows', 'Lorvex.exe'), 'windows');
  writeFile(path.join(distRoot, 'macos', 'Lorvex.dmg'), 'macos');
  writeFile(path.join(distRoot, 'macos', 'Lorvex.dmg.sig'), 'macos-sig');
  writeFile(outputPath, 'stale');

  const result = createReleaseChecksums({
    root: distRoot,
    outputPath,
  });

  assert.deepEqual(result.entries, [
    'macos/Lorvex.dmg',
    'macos/Lorvex.dmg.sig',
    'windows/Lorvex.exe',
  ]);
  assert.equal(
    fs.readFileSync(outputPath, 'utf8'),
    [
      `${sha256('macos')}  macos/Lorvex.dmg`,
      `${sha256('macos-sig')}  macos/Lorvex.dmg.sig`,
      `${sha256('windows')}  windows/Lorvex.exe`,
      '',
    ].join('\n'),
  );
});

test('createReleaseChecksums can scope checksums to explicit artifact files and folders', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-checksums-scoped-'));
  const distRoot = path.join(tempRoot, 'dist');
  const outputPath = path.join(tempRoot, 'SHA256SUMS');

  writeFile(path.join(distRoot, 'macos', 'Lorvex.dmg'), 'macos');
  writeFile(path.join(distRoot, 'macos', 'Lorvex.dmg.sig'), 'macos-sig');
  writeFile(path.join(distRoot, 'debug', 'scratch.txt'), 'debug');
  writeFile(path.join(distRoot, 'latest.json'), '{"version":"0.1.0"}');

  const result = createReleaseChecksums({
    root: distRoot,
    outputPath,
    artifacts: [
      path.join(distRoot, 'macos'),
      path.join(distRoot, 'latest.json'),
    ],
  });

  assert.deepEqual(result.entries, [
    'latest.json',
    'macos/Lorvex.dmg',
    'macos/Lorvex.dmg.sig',
  ]);
  assert.doesNotMatch(fs.readFileSync(outputPath, 'utf8'), /debug/);
});

test('createReleaseChecksums can emit release-asset basenames for GitHub Release downloads', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-release-checksums-basename-'));
  const outputPath = path.join(tempRoot, 'SHA256SUMS');

  writeFile(path.join(tempRoot, 'dist', 'macos', 'Lorvex.dmg'), 'macos');
  writeFile(path.join(tempRoot, 'latest.json'), '{"version":"0.1.0"}');

  const result = createReleaseChecksums({
    root: tempRoot,
    outputPath,
    artifacts: [
      path.join(tempRoot, 'dist', 'macos'),
      path.join(tempRoot, 'latest.json'),
    ],
    entryMode: 'basename',
  });

  assert.deepEqual(result.entries, [
    'latest.json',
    'Lorvex.dmg',
  ]);
});
