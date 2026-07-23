import fs from 'node:fs';
import path from 'node:path';

const CSS_IMPORT_RE = /^\s*@import\s+(?:url\()?['"]([^'"]+)['"]\)?\s*;/gm;

function isLocalImport(specifier) {
  return specifier.startsWith('./') || specifier.startsWith('../') || specifier.startsWith('/');
}

export function resolveCssImportGraph(entryPath, {
  seen = new Set(),
  includeExternalImports = true,
} = {}) {
  const absoluteEntryPath = path.resolve(entryPath);
  if (seen.has(absoluteEntryPath)) {
    throw new Error(`CSS import cycle detected at ${absoluteEntryPath}`);
  }
  if (!fs.existsSync(absoluteEntryPath)) {
    throw new Error(`Missing CSS entry: ${absoluteEntryPath}`);
  }

  seen.add(absoluteEntryPath);
  const source = fs.readFileSync(absoluteEntryPath, 'utf8');
  const resolved = source.replace(CSS_IMPORT_RE, (statement, specifier) => {
    if (!isLocalImport(specifier)) {
      return includeExternalImports ? statement : '';
    }

    const importedPath = path.resolve(path.dirname(absoluteEntryPath), specifier);
    return resolveCssImportGraph(importedPath, { seen, includeExternalImports });
  });
  seen.delete(absoluteEntryPath);
  return resolved;
}
