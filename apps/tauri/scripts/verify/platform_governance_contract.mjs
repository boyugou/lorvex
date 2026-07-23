#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(message) {
  console.error(`[verify:platform-governance-contract] ${message}`);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function parseMode(argv) {
  const explicitMode = argv.find((arg) => arg.startsWith('--mode='));
  if (explicitMode) {
    return explicitMode.split('=', 2)[1] ?? '';
  }
  if (argv.includes('--enforce')) {
    return 'new-only';
  }
  return 'advisory';
}

function collectSourceFiles(rootDir) {
  const files = [];
  const stack = [rootDir];

  while (stack.length > 0) {
    const current = stack.pop();
    if (!current) {
      continue;
    }

    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (entry.isFile() && (entry.name.endsWith('.ts') || entry.name.endsWith('.tsx'))) {
        files.push(fullPath);
      }
    }
  }

  return files.sort();
}

function computeLineNumber(source, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) {
    if (source[i] === '\n') {
      line += 1;
    }
  }
  return line;
}

function lineAt(source, lineNumber) {
  const lines = source.split('\n');
  return (lines[lineNumber - 1] ?? '').trim();
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const appSrcRoot = path.join(repoRoot, 'app', 'src');

assert(fs.existsSync(appSrcRoot), 'missing app/src directory');

// `platform.ts` was decomposed into a thin re-export façade plus
// `platform.logic.ts`, which now owns the user-agent sniffing
// implementation that this contract gates. Both modules are canonical
// so the user-agent / OS-string regexes are not flagged on the
// source-of-truth file. main.tsx similarly delegates the document
// runtime install to `main.runtime.ts`; it stays canonical for the
// platform-attribute setters' allowlist.
const canonicalModules = new Set([
  'app/src/lib/platform/platform.ts',
  'app/src/lib/platform/platform.logic.ts',
  'app/src/main.tsx',
]);

for (const canonical of canonicalModules) {
  assert(fs.existsSync(path.join(repoRoot, canonical)), `missing canonical module: ${canonical}`);
}

const allowlist = [];

const bannedPatterns = [
  {
    id: 'navigator-user-agent',
    description: 'direct navigator.userAgent usage outside canonical capability module',
    regex: /navigator\.userAgent/g,
  },
  {
    id: 'user-agent-lowercase',
    description: 'direct userAgent.toLowerCase parsing outside canonical capability module',
    regex: /userAgent\.toLowerCase\(/g,
  },
  {
    id: 'os-string-windows',
    description: "ad-hoc platform string check includes('windows') outside canonical capability module",
    regex: /includes\(\s*['"]windows['"]\s*\)/g,
  },
  {
    id: 'os-string-macintosh',
    description: "ad-hoc platform string check includes('macintosh') outside canonical capability module",
    regex: /includes\(\s*['"]macintosh['"]\s*\)/g,
  },
  {
    id: 'os-string-linux',
    description: "ad-hoc platform string check includes('linux') outside canonical capability module",
    regex: /includes\(\s*['"]linux['"]\s*\)/g,
  },
  {
    id: 'os-string-android',
    description: "ad-hoc platform string check includes('android') outside canonical capability module",
    regex: /includes\(\s*['"]android['"]\s*\)/g,
  },
  {
    id: 'os-string-iphone',
    description: "ad-hoc platform string check includes('iphone') outside canonical capability module",
    regex: /includes\(\s*['"]iphone['"]\s*\)/g,
  },
  {
    id: 'os-string-ipad',
    description: "ad-hoc platform string check includes('ipad') outside canonical capability module",
    regex: /includes\(\s*['"]ipad['"]\s*\)/g,
  },
];

function isAllowlisted(file, patternId) {
  return allowlist.some((entry) => {
    if (entry.file !== file) {
      return false;
    }
    return entry.patterns.includes('*') || entry.patterns.includes(patternId);
  });
}

const mode = parseMode(process.argv.slice(2));
const allowedModes = new Set(['advisory', 'new-only', 'strict']);
assert(allowedModes.has(mode), `unsupported mode "${mode}". Expected one of: advisory, new-only, strict`);

const sourceFiles = collectSourceFiles(appSrcRoot);
const findings = [];

for (const absolutePath of sourceFiles) {
  const relativePath = path.relative(repoRoot, absolutePath).replaceAll(path.sep, '/');
  if (canonicalModules.has(relativePath)) {
    continue;
  }

  const source = fs.readFileSync(absolutePath, 'utf8');
  for (const pattern of bannedPatterns) {
    for (const match of source.matchAll(pattern.regex)) {
      const index = match.index ?? 0;
      const lineNumber = computeLineNumber(source, index);
      findings.push({
        file: relativePath,
        line: lineNumber,
        patternId: pattern.id,
        description: pattern.description,
        snippet: lineAt(source, lineNumber),
        allowlisted: isAllowlisted(relativePath, pattern.id),
      });
    }
  }
}

const allowlistedFindings = findings.filter((finding) => finding.allowlisted);
const nonAllowlistedFindings = findings.filter((finding) => !finding.allowlisted);

console.log(`[verify:platform-governance-contract] mode=${mode}`);
console.log(`[verify:platform-governance-contract] scanned ${sourceFiles.length} app/src TypeScript files`);
console.log(
  `[verify:platform-governance-contract] findings: total=${findings.length}, allowlisted=${allowlistedFindings.length}, non_allowlisted=${nonAllowlistedFindings.length}`,
);

if (allowlistedFindings.length > 0) {
  console.log('[verify:platform-governance-contract] allowlisted findings:');
  for (const finding of allowlistedFindings) {
    console.log(
      `  - ${finding.file}:${finding.line} [${finding.patternId}] ${finding.snippet}`,
    );
  }
}

if (nonAllowlistedFindings.length > 0) {
  console.log('[verify:platform-governance-contract] non-allowlisted findings:');
  for (const finding of nonAllowlistedFindings) {
    console.log(
      `  - ${finding.file}:${finding.line} [${finding.patternId}] ${finding.snippet}`,
    );
  }
}

if (mode === 'strict' && findings.length > 0) {
  fail(`strict mode blocked ${findings.length} finding(s)`);
}

if (mode === 'new-only' && nonAllowlistedFindings.length > 0) {
  fail(`new-only mode blocked ${nonAllowlistedFindings.length} non-allowlisted finding(s)`);
}

if (mode === 'advisory' && nonAllowlistedFindings.length > 0) {
  console.log(
    `[verify:platform-governance-contract] advisory: detected ${nonAllowlistedFindings.length} non-allowlisted finding(s); not failing build in advisory mode`,
  );
}

console.log('[verify:platform-governance-contract] Platform governance contract checks passed.');
