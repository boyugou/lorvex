import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export const fixturesRoot = path.resolve(here, 'fixtures');
export const repoRoot = path.resolve(here, '..', '..', '..');

function escapeForRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function readRustSources(...relativePaths) {
  return relativePaths
    .map((relativePath) => readRustSourceEntry(path.join(repoRoot, relativePath)))
    .join('\n');
}

export function readTypeScriptSources(...relativePaths) {
  return relativePaths
    .map((relativePath) => readTypeScriptSourceEntry(path.join(repoRoot, relativePath)))
    .join('\n');
}

export function readAppSources() {
  return readTypeScriptSources('app/src/App.tsx', 'app/src/app-shell');
}

export function readIpcSources() {
  return readTypeScriptSources('app/src/lib/ipc');
}

export function rustModuleDeclarationFileNames(source, {
  includeRoot = true,
} = {}) {
  const moduleNames = new Set();
  const moduleDeclaration = /^(?:\s*#\[[^\n]+\]\s*\n)*\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z0-9_]+)\s*;/gm;
  let match;
  while ((match = moduleDeclaration.exec(source)) !== null) {
    moduleNames.add(`${match[1]}.rs`);
  }
  const files = [...moduleNames];
  if (includeRoot) {
    files.push('mod.rs');
  }
  return files.sort((left, right) => left.localeCompare(right));
}

export function rustModuleDeclarationPattern(moduleName) {
  return new RegExp(`^(?:pub\\(crate\\)\\s+)?mod\\s+${escapeForRegExp(moduleName)};$`, 'm');
}

function readRustSourceEntry(absolutePath) {
  const stats = fs.statSync(absolutePath);
  if (stats.isDirectory()) {
    return fs
      .readdirSync(absolutePath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
      .map((entry) => {
        if (entry.isDirectory()) {
          return readRustSourceEntry(path.join(absolutePath, entry.name));
        }
        if (entry.isFile() && entry.name.endsWith('.rs')) {
          return fs.readFileSync(path.join(absolutePath, entry.name), 'utf8');
        }
        return '';
      })
      .filter(Boolean)
      .join('\n');
  }

  return fs.readFileSync(absolutePath, 'utf8');
}

function readTypeScriptSourceEntry(absolutePath) {
  const stats = fs.statSync(absolutePath);
  if (stats.isDirectory()) {
    return fs
      .readdirSync(absolutePath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
      .map((entry) => {
        if (entry.isDirectory()) {
          return readTypeScriptSourceEntry(path.join(absolutePath, entry.name));
        }
        if (entry.isFile() && (entry.name.endsWith('.ts') || entry.name.endsWith('.tsx'))) {
          return fs.readFileSync(path.join(absolutePath, entry.name), 'utf8');
        }
        return '';
      })
      .filter(Boolean)
      .join('\n');
  }

  return fs.readFileSync(absolutePath, 'utf8');
}

export function extractRustFunctionBody(source, functionName) {
  const signaturePatterns = [
    `pub fn ${functionName}`,
    `pub(crate) fn ${functionName}`,
    `pub async fn ${functionName}`,
    `pub(crate) async fn ${functionName}`,
    `fn ${functionName}`,
  ];
  const start = signaturePatterns
    .map((signature) => source.indexOf(signature))
    .find((index) => index !== -1);
  if (start === undefined) {
    throw new Error(`Expected ${functionName} in provided Rust source`);
  }

  const bodyStart = source.indexOf('{', start);
  if (bodyStart === -1) {
    throw new Error(`Expected ${functionName} body start`);
  }

  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    const char = source[index];
    if (char === '{') depth += 1;
    if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(bodyStart + 1, index);
      }
    }
  }

  throw new Error(`Failed to extract ${functionName} body`);
}

function normalizeRustWhitespace(source) {
  return source.replace(/\s+/g, ' ').trim();
}

function collectRustUseStatements(source) {
  return Array.from(
    source.matchAll(/(?:#\[[^\]]+\]\s*)*(pub(?:\(crate\))?\s+use\s+[\s\S]*?;)/g),
    (match) => normalizeRustWhitespace(match[1]),
  );
}

export function hasRustUseReexport(source, { modulePath, symbols, visibility = null }) {
  const expectedSymbols = Array.isArray(symbols) ? symbols : [symbols];
  const useStatements = collectRustUseStatements(source).filter((statement) => {
    if (visibility !== null) {
      const expectedPrefix = visibility === 'pub'
        ? 'pub use '
        : visibility.startsWith('pub(')
          ? `${visibility} use `
          : `pub(${visibility}) use `;
      if (!statement.startsWith(expectedPrefix)) {
        return false;
      }
    }
    if (!statement.includes(`use ${modulePath}::`)) {
      return false;
    }
    return true;
  });

  if (useStatements.length === 0) {
    return false;
  }

  return expectedSymbols.every((symbol) => (
    useStatements.some((statement) => new RegExp(`\\b${escapeForRegExp(symbol)}\\b`).test(statement))
  ));
}
