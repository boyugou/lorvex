#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const CHECKSUM_FILE_NAME = 'SHA256SUMS';

function fail(message) {
  throw new Error(`[write_checksums] ${message}`);
}

function toPosixPath(value) {
  return value.split(path.sep).join('/');
}

function parseArgs(argv) {
  const options = {
    root: null,
    output: null,
    artifacts: [],
    entryMode: 'relative',
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const readValue = () => {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        fail(`${arg} requires a value`);
      }
      index += 1;
      return value;
    };

    if (arg === '--root') {
      options.root = readValue();
    } else if (arg === '--output') {
      options.output = readValue();
    } else if (arg === '--artifact') {
      options.artifacts.push(readValue());
    } else if (arg === '--entry-mode') {
      options.entryMode = readValue();
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else {
      fail(`Unknown argument: ${arg}`);
    }
  }

  if (!options.root) {
    fail('--root is required');
  }
  if (!options.output) {
    fail('--output is required');
  }
  if (!['relative', 'basename'].includes(options.entryMode)) {
    fail('--entry-mode must be relative or basename');
  }

  return options;
}

function printHelp() {
  console.log(`Usage: node scripts/release/write_checksums.mjs --root <dir> --output <file> [--artifact <path> ...] [--entry-mode relative|basename]

Computes SHA-256 checksums for release artifacts. Paths in ${CHECKSUM_FILE_NAME}
are written relative to --root and sorted lexicographically.`);
}

function walkFiles(targetPath) {
  const stat = fs.statSync(targetPath);
  if (stat.isFile()) {
    return [targetPath];
  }
  if (!stat.isDirectory()) {
    return [];
  }

  return fs
    .readdirSync(targetPath, { withFileTypes: true })
    .sort((left, right) => left.name.localeCompare(right.name))
    .flatMap((entry) => walkFiles(path.join(targetPath, entry.name)));
}

function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
}

export function createReleaseChecksums({
  root,
  outputPath,
  artifacts = [],
  entryMode = 'relative',
} = {}) {
  if (!root) {
    fail('root is required');
  }
  if (!outputPath) {
    fail('outputPath is required');
  }
  if (!['relative', 'basename'].includes(entryMode)) {
    fail('entryMode must be relative or basename');
  }

  const rootPath = path.resolve(root);
  const resolvedOutputPath = path.resolve(outputPath);
  if (!fs.existsSync(rootPath) || !fs.statSync(rootPath).isDirectory()) {
    fail(`root must be an existing directory: ${rootPath}`);
  }

  const sourcePaths = artifacts.length > 0
    ? artifacts.map((artifactPath) => path.resolve(artifactPath))
    : [rootPath];

  const files = sourcePaths.flatMap((sourcePath) => {
    if (!fs.existsSync(sourcePath)) {
      fail(`artifact path does not exist: ${sourcePath}`);
    }
    return walkFiles(sourcePath);
  });

  const entryNames = new Set();
  const uniqueFiles = Array.from(new Set(files.map((filePath) => path.resolve(filePath))))
    .filter((filePath) => filePath !== resolvedOutputPath)
    .filter((filePath) => path.basename(filePath) !== CHECKSUM_FILE_NAME)
    .map((filePath) => {
      const relativePath = path.relative(rootPath, filePath);
      if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
        fail(`artifact path must be inside root: ${filePath}`);
      }
      const entryPath = entryMode === 'basename' ? path.basename(filePath) : toPosixPath(relativePath);
      if (entryNames.has(entryPath)) {
        fail(`duplicate checksum entry path: ${entryPath}`);
      }
      entryNames.add(entryPath);
      return {
        filePath,
        entryPath,
      };
    })
    .sort((left, right) => left.entryPath.localeCompare(right.entryPath));

  if (uniqueFiles.length === 0) {
    fail('no files found to checksum');
  }

  const lines = uniqueFiles.map(({ filePath, entryPath }) => `${sha256File(filePath)}  ${entryPath}`);
  fs.mkdirSync(path.dirname(resolvedOutputPath), { recursive: true });
  fs.writeFileSync(resolvedOutputPath, `${lines.join('\n')}\n`, 'utf8');

  return {
    outputPath: resolvedOutputPath,
    entries: uniqueFiles.map(({ entryPath }) => entryPath),
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArgs(process.argv.slice(2));
    const result = createReleaseChecksums({
      root: options.root,
      outputPath: options.output,
      artifacts: options.artifacts,
      entryMode: options.entryMode,
    });
    console.log(`[write_checksums] wrote ${result.entries.length} entries to ${result.outputPath}`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
