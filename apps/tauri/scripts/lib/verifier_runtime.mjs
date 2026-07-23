import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export function resolveRepoRootFromMeta(metaUrl) {
  const scriptPath = fileURLToPath(metaUrl);
  let current = path.dirname(scriptPath);
  while (true) {
    const packageJsonPath = path.join(current, 'package.json');
    const claudePath = path.join(current, 'CLAUDE.md');
    if (fs.existsSync(packageJsonPath) && fs.existsSync(claudePath)) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(`Unable to resolve repo root from ${scriptPath}`);
    }
    current = parent;
  }
}

export function assertContract(condition, scriptTag, message) {
  if (!condition) {
    throw new Error(`${scriptTag} ${message}`);
  }
}

export function runVerifierCli({ scriptTag, successMessage, run }) {
  try {
    run();
    if (successMessage) {
      console.log(`${scriptTag} ${successMessage}`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(scriptTag) ? message : `${scriptTag} ${message}`);
    process.exit(1);
  }
}

export function readSourceTree(rootPath, { exts = ['.ts', '.tsx'] } = {}) {
  if (!fs.existsSync(rootPath)) {
    throw new Error(`Missing required file: ${rootPath}`);
  }

  const stats = fs.statSync(rootPath);
  if (stats.isDirectory()) {
    return fs
      .readdirSync(rootPath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
      .map((entry) => readSourceTree(path.join(rootPath, entry.name), { exts }))
      .filter(Boolean)
      .join('\n');
  }

  if (!exts.some((ext) => rootPath.endsWith(ext))) {
    return '';
  }

  return fs.readFileSync(rootPath, 'utf8');
}

export function stripSourceComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^\\:])\/\/.*$/gm, '$1');
}
