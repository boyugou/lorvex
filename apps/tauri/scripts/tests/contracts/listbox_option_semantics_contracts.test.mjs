import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const APP_SRC = path.join(repoRoot, 'app/src');
const TSX_EXTENSIONS = new Set(['.ts', '.tsx']);

function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
}

function collectSourceFiles(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectSourceFiles(fullPath, files);
      continue;
    }
    if (TSX_EXTENSIONS.has(path.extname(entry.name))) {
      files.push(fullPath);
    }
  }
  return files;
}

function findOpeningTagEnd(source, startIndex) {
  let braceDepth = 0;
  let quote = null;

  for (let i = startIndex; i < source.length; i += 1) {
    const char = source[i];
    const previous = source[i - 1];

    if (quote) {
      if (char === quote && previous !== '\\') {
        quote = null;
      }
      continue;
    }

    if (char === '"' || char === "'" || char === '`') {
      quote = char;
      continue;
    }

    if (char === '{') {
      braceDepth += 1;
      continue;
    }

    if (char === '}') {
      braceDepth = Math.max(0, braceDepth - 1);
      continue;
    }

    if (char === '>' && braceDepth === 0) {
      return i;
    }
  }

  return -1;
}

function findButtonOpeningTags(source) {
  const uncommented = stripComments(source);
  const tags = [];
  const buttonStartPattern = /<button\b/g;
  let match;

  while ((match = buttonStartPattern.exec(uncommented)) !== null) {
    const startIndex = match.index;
    const endIndex = findOpeningTagEnd(uncommented, startIndex);
    if (endIndex < 0) break;
    tags.push({
      index: startIndex,
      source: uncommented.slice(startIndex, endIndex + 1),
    });
    buttonStartPattern.lastIndex = endIndex + 1;
  }

  return tags;
}

function findButtonRoleOptionViolations(source) {
  return findButtonOpeningTags(source).filter((tag) => (
    /\brole\s*=\s*(?:"option"|'option'|\{\s*["']option["']\s*\})/.test(tag.source)
  ));
}

test('listbox options never use native button elements', () => {
  const offenders = [];
  for (const filePath of collectSourceFiles(APP_SRC)) {
    const source = fs.readFileSync(filePath, 'utf8');
    const matches = findButtonRoleOptionViolations(source);
    for (const match of matches) {
      offenders.push(`${path.relative(repoRoot, filePath)}:${source.slice(0, match.index).split('\n').length}`);
    }
  }

  assert.deepEqual(
    offenders,
    [],
    `Use a non-button element such as <div role="option"> for listbox options:\n${offenders.join('\n')}`,
  );
});

test('listbox option scanner ignores comments and rejects button options', () => {
  assert.equal(
    findButtonRoleOptionViolations('/* <button role="option"> */\n// <button role="option">\n<div role="option" />').length,
    0,
  );
  assert.equal(findButtonRoleOptionViolations('<button type="button" role="option" />').length, 1);
  assert.equal(findButtonRoleOptionViolations("<button role={'option'} />").length, 1);
  assert.equal(
    findButtonRoleOptionViolations(`<button
      ref={(el) => { optionRefs.current[i] = el; }}
      type="button"
      role="option"
    />`).length,
    1,
  );
});
