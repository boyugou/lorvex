import assert from 'node:assert/strict';
import test from 'node:test';

import { buildSentinelMaps } from '../../../verify/_forbidden_pattern.mjs';

// #3807 — markers inside a string literal must NOT be honored, only
// markers inside a comment. Otherwise an arbitrary `const FOO =
// "@verify-exempt: bypass-everything"` could silently allowlist a line
// the gate should be flagging. Comment-context is enforced by
// `COMMENT_PREFIX_RE` inside `buildSentinelMaps`.
test('buildSentinelMaps ignores @verify-exempt inside string literals', () => {
  const lines = [
    '// real comment marker',
    '/* @verify-exempt: comment-form */',
    'const stringLit = "@verify-exempt: string-form";',
    'const tplLit = `@verify-exempt: template-form`;',
    '   // @verify-exempt: indented-comment',
    '/* @verify-exempt-next: next-line-form */',
    'const targetForNext = 1;',
    ' * @verify-exempt: block-continuation',
    '# @verify-exempt: shell-comment',
  ];
  const { sentinelMap, sentinelNextMap } = buildSentinelMaps(lines, 'fixture.ts');

  // Comment forms recorded.
  assert.equal(sentinelMap.get('comment-form'), 2);
  assert.equal(sentinelMap.get('indented-comment'), 5);
  assert.equal(sentinelMap.get('block-continuation'), 8);
  assert.equal(sentinelMap.get('shell-comment'), 9);

  // String / template literal forms NOT recorded.
  assert.equal(sentinelMap.has('string-form'), false);
  assert.equal(sentinelMap.has('template-form'), false);

  // Next-line form resolves to marker line + 1.
  assert.equal(sentinelNextMap.get('next-line-form'), 7);
  // ...and is NOT also recorded in the this-line map.
  assert.equal(sentinelMap.has('next-line-form'), false);
});

// #3808 — `@verify-exempt-next` resolves to the line immediately
// following the marker line. The two maps are kept disjoint so a
// single name cannot resolve to two different lines.
test('buildSentinelMaps records @verify-exempt-next on next-line map only', () => {
  const lines = [
    '// some preamble',
    '/* @verify-exempt-next: foo */',
    'forbidden token here',
  ];
  const { sentinelMap, sentinelNextMap } = buildSentinelMaps(lines, 'fixture.ts');
  assert.equal(sentinelNextMap.get('foo'), 3);
  assert.equal(sentinelMap.has('foo'), false);
});

// #3823 — duplicate sentinel name across the two maps must FATAL with
// a thrown Error rather than silently honoring the first hit.
// `buildSentinelMaps` is pure (#3823 refactor) so the test harness can
// assert on the throw directly instead of forking a subprocess to
// observe `process.exit(1)`.
test('buildSentinelMaps throws on duplicate sentinel within sentinelMap', () => {
  const lines = [
    '// @verify-exempt: dup',
    '// @verify-exempt: dup',
  ];
  assert.throws(
    () => buildSentinelMaps(lines, 'fixture.ts'),
    /FATAL: duplicate sentinel @dup on lines 1 and 2 in fixture\.ts/,
  );
});

test('buildSentinelMaps throws on duplicate sentinel name across this-line + next-line maps', () => {
  const lines = [
    '/* @verify-exempt-next: shared */',
    'forbidden token',
    '// @verify-exempt: shared',
  ];
  assert.throws(
    () => buildSentinelMaps(lines, 'fixture.ts'),
    /FATAL: duplicate sentinel @shared/,
  );
});

// #3807 + #3823 — markers must sit on their own comment line.
// `COMMENT_PREFIX_RE` anchors the comment opener (`//`, `#`, `--`,
// `/*`, ` *`) to the line start (modulo whitespace), so a
// mid-expression `/* @verify-exempt: x */` is NOT recognised as a
// valid exemption marker.
test('buildSentinelMaps rejects mid-expression /* @verify-exempt: ... */', () => {
  const lines = [
    'const x = 1; /* @verify-exempt: mid-expr */',
  ];
  const { sentinelMap, sentinelNextMap } = buildSentinelMaps(lines, 'fixture.ts');
  assert.equal(sentinelMap.has('mid-expr'), false);
  assert.equal(sentinelNextMap.has('mid-expr'), false);
});

// #3823 — the SQL `--` comment prefix is a recognised comment opener
// alongside `//`, `#`, `/*`, ` *`. SQL migration files can host
// exemption markers without an HTML/JS-style comment.
test('buildSentinelMaps records markers on SQL -- comment lines', () => {
  const lines = [
    '-- @verify-exempt: sql-form',
    '   -- @verify-exempt: indented-sql-form',
  ];
  const { sentinelMap } = buildSentinelMaps(lines, 'migration.sql');
  assert.equal(sentinelMap.get('sql-form'), 1);
  assert.equal(sentinelMap.get('indented-sql-form'), 2);
});
