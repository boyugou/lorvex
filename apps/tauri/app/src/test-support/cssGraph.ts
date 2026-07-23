type FsModule = { readFileSync: (path: string, encoding: string) => string };

const CSS_IMPORT_RE = /^\s*@import\s+(?:url\()?['"]([^'"]+)['"]\)?\s*;/gm;

function dirname(filePath: string): string {
  const index = filePath.lastIndexOf('/');
  return index === -1 ? '.' : filePath.slice(0, index);
}

function normalize(pathname: string): string {
  const isAbsolute = pathname.startsWith('/');
  const parts: string[] = [];

  for (const part of pathname.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') {
      parts.pop();
      continue;
    }
    parts.push(part);
  }

  return `${isAbsolute ? '/' : ''}${parts.join('/')}`;
}

function resolveImport(fromPath: string, specifier: string): string {
  if (specifier.startsWith('/')) return normalize(specifier);
  return normalize(`${dirname(fromPath)}/${specifier}`);
}

function isLocalImport(specifier: string): boolean {
  return specifier.startsWith('./') || specifier.startsWith('../') || specifier.startsWith('/');
}

export function readCssImportGraph(fs: FsModule, entryPath: string, seen = new Set<string>()): string {
  const normalizedEntryPath = normalize(entryPath);
  if (seen.has(normalizedEntryPath)) {
    throw new Error(`CSS import cycle detected at ${normalizedEntryPath}`);
  }

  seen.add(normalizedEntryPath);
  const source = fs.readFileSync(normalizedEntryPath, 'utf8');
  const resolved = source.replace(CSS_IMPORT_RE, (statement, specifier: string) => {
    if (!isLocalImport(specifier)) return statement;
    return readCssImportGraph(fs, resolveImport(normalizedEntryPath, specifier), seen);
  });
  seen.delete(normalizedEntryPath);
  return resolved;
}
