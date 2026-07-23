#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(message) {
  throw new Error(`[create_release_manifest] ${message}`);
}

function ensureDir(dirPath, label) {
  if (!fs.existsSync(dirPath) || !fs.statSync(dirPath).isDirectory()) {
    fail(`${label} missing: ${dirPath}`);
  }
}

function listFiles(dirPath, predicate) {
  ensureDir(dirPath, 'Artifacts directory');
  return fs.readdirSync(dirPath)
    .filter((name) => predicate(name))
    .sort((a, b) => a.localeCompare(b));
}

function listFilesRecursive(dirPath, predicate) {
  ensureDir(dirPath, 'Artifacts directory');
  const files = [];

  function walk(currentDir, relativeDir = '') {
    for (const entry of fs.readdirSync(currentDir, { withFileTypes: true })) {
      const relativePath = relativeDir ? path.join(relativeDir, entry.name) : entry.name;
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath, relativePath);
        continue;
      }
      if (entry.isFile() && predicate(entry.name)) {
        files.push(relativePath.split(path.sep).join('/'));
      }
    }
  }

  walk(dirPath);
  return files.sort((a, b) => a.localeCompare(b));
}

function readSignature(filePath) {
  const signaturePath = `${filePath}.sig`;
  if (!fs.existsSync(signaturePath)) {
    fail(`Missing updater signature: ${signaturePath}`);
  }

  const signature = fs.readFileSync(signaturePath, 'utf8').trim();
  if (!signature) {
    fail(`Empty updater signature: ${signaturePath}`);
  }

  return signature;
}

function buildReleaseUrl(githubRepository, tag, fileName) {
  return `https://github.com/${githubRepository}/releases/download/${tag}/${fileName}`;
}

function selectDarwinArtifacts(macosDir) {
  const dmgFiles = listFiles(macosDir, (name) => name.endsWith('.dmg'));
  const byPlatform = new Map();

  for (const fileName of dmgFiles) {
    const lower = fileName.toLowerCase();
    if (lower.includes('universal')) {
      if (!byPlatform.has('darwin-aarch64')) byPlatform.set('darwin-aarch64', fileName);
      if (!byPlatform.has('darwin-x86_64')) byPlatform.set('darwin-x86_64', fileName);
    } else if (lower.includes('aarch64') || lower.includes('arm64')) {
      byPlatform.set('darwin-aarch64', fileName);
    } else if (lower.includes('x64') || lower.includes('x86_64')) {
      byPlatform.set('darwin-x86_64', fileName);
    }
  }

  return { dmgFiles, byPlatform };
}

function createAllDesktopPlatforms({ distRoot, githubRepository, tag }) {
  const macosDir = path.join(distRoot, 'macos');
  const windowsDir = path.join(distRoot, 'windows');
  const linuxDir = path.join(distRoot, 'linux');
  const { byPlatform } = selectDarwinArtifacts(macosDir);
  const windowsExe = listFiles(windowsDir, (name) => name.endsWith('.exe') && !name.endsWith('.exe.sig'))[0];

  if (!byPlatform.has('darwin-aarch64') || !byPlatform.has('darwin-x86_64') || !windowsExe) {
    fail('Missing expected desktop release bundles (darwin-aarch64, darwin-x86_64, windows-x86_64).');
  }

  const macArm = byPlatform.get('darwin-aarch64');
  const macX64 = byPlatform.get('darwin-x86_64');

  const platforms = {
    'darwin-aarch64': {
      url: buildReleaseUrl(githubRepository, tag, macArm),
      signature: readSignature(path.join(macosDir, macArm)),
    },
    'darwin-x86_64': {
      url: buildReleaseUrl(githubRepository, tag, macX64),
      signature: readSignature(path.join(macosDir, macX64)),
    },
    'windows-x86_64': {
      url: buildReleaseUrl(githubRepository, tag, windowsExe),
      signature: readSignature(path.join(windowsDir, windowsExe)),
    },
  };

  // Add Linux AppImage if available (not required — Linux builds may be absent)
  if (fs.existsSync(linuxDir)) {
    const linuxAppImage = listFilesRecursive(linuxDir, (name) => name.endsWith('.AppImage') && !name.endsWith('.AppImage.sig'))[0];
    if (linuxAppImage) {
      platforms['linux-x86_64'] = {
        url: buildReleaseUrl(githubRepository, tag, path.basename(linuxAppImage)),
        signature: readSignature(path.join(linuxDir, linuxAppImage)),
      };
    }
  }

  return platforms;
}

function createMacosOnlyPlatforms({ distRoot, githubRepository, tag, fallbackMacosPlatform }) {
  const macosDir = path.join(distRoot, 'macos');
  const { dmgFiles, byPlatform } = selectDarwinArtifacts(macosDir);

  if (dmgFiles.length === 0) {
    fail('Missing macOS dmg artifacts in dist/macos.');
  }

  if (byPlatform.size === 0) {
    const fallbackFile = dmgFiles[0];
    return {
      [fallbackMacosPlatform]: {
        url: buildReleaseUrl(githubRepository, tag, fallbackFile),
        signature: readSignature(path.join(macosDir, fallbackFile)),
      },
    };
  }

  return Object.fromEntries(
    [...byPlatform.entries()].map(([platform, fileName]) => ([
      platform,
      {
        url: buildReleaseUrl(githubRepository, tag, fileName),
        signature: readSignature(path.join(macosDir, fileName)),
      },
    ])),
  );
}

export function createReleaseManifest({
  mode = 'desktop',
  distRoot = 'dist',
  githubRepository = process.env.GITHUB_REPOSITORY,
  tag = process.env.GITHUB_REF_NAME,
  outputPath,
  fallbackMacosPlatform = process.arch === 'arm64' ? 'darwin-aarch64' : 'darwin-x86_64',
  now = new Date(),
} = {}) {
  if (!githubRepository) fail('Missing GitHub repository slug. Pass --github-repository or set GITHUB_REPOSITORY.');
  if (!tag) fail('Missing git tag. Pass --tag or set GITHUB_REF_NAME.');

  const normalizedMode = mode.toLowerCase();
  const manifest = {
    version: normalizedMode === 'macos-only'
      ? tag.replace(/^mac-v/, '')
      : tag.replace(/^v/, ''),
    notes: 'See the release page for details.',
    pub_date: now.toISOString(),
    platforms: normalizedMode === 'macos-only'
      ? createMacosOnlyPlatforms({ distRoot, githubRepository, tag, fallbackMacosPlatform })
      : createAllDesktopPlatforms({ distRoot, githubRepository, tag }),
  };

  const targetPath = outputPath ?? (normalizedMode === 'macos-only' ? 'latest-macos.json' : 'latest.json');
  fs.writeFileSync(targetPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');

  return { manifest, outputPath: targetPath };
}

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) {
      fail(`Missing value for --${key}`);
    }
    options[key] = value;
    index += 1;
  }
  return options;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2));
  const { outputPath } = createReleaseManifest({
    mode: args.mode,
    distRoot: args['dist-root'],
    githubRepository: args['github-repository'],
    tag: args.tag,
    outputPath: args.output,
    fallbackMacosPlatform: args['fallback-macos-platform'],
  });
  console.log(`[create_release_manifest] Wrote ${outputPath}`);
}
