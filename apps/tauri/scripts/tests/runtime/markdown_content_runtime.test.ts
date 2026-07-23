import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

test('MarkdownContent defaults rendered markdown to selectable text', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/MarkdownContent.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /className=\{`markdown-content select-text-content \$\{className \?\? ''\}`\}/,
  );
});

test('MarkdownContent keeps link navigation routed through the safe opener path', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/MarkdownContent.tsx'),
    'utf8',
  );

  assert.match(source, /const allowed = isAllowedLinkUrl\(href\);/);
  assert.match(source, /e\.preventDefault\(\);/);
  assert.match(source, /void openUrl\(href\)\.catch\(/);
  assert.match(source, /href=\{allowed \? href : '#'\}/);
});
