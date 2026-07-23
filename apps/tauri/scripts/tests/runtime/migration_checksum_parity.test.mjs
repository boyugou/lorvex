import assert from 'node:assert/strict';
import test from 'node:test';

import {
  normalizeMigrationSql,
  sha256MigrationHex,
} from '../../verify/migration_checksums.mjs';

// Cross-language parity contract — see issue #2972.
//
// `sha256MigrationHex` (this verifier) and `lorvex-store::migration::
// checksum::sha256_hex` (the Rust runtime) MUST produce the same hex
// digest for the same SQL text. Until #2972 they drifted: the runtime
// trimmed + LF-normalized + BOM-stripped before hashing while the
// verifier hashed raw bytes. A Windows clone with `core.autocrlf=true`
// editing a migration could make the verifier pass while the runtime
// trips ChecksumMismatch on first launch.
//
// REFERENCE_HASH below is the SHA-256 of the bytes
//   "CREATE TABLE t (id INTEGER);"
// (no leading/trailing whitespace, LF only). The Rust unit test
// `lorvex-store::migration::checksum::tests::parity_with_verifier_reference_hash`
// hashes the SAME bytes against the same constant. If you change either
// constant you MUST change both — they are how we keep the two
// implementations from drifting again.
const REFERENCE_INPUT_CANONICAL = 'CREATE TABLE t (id INTEGER);';
const REFERENCE_HASH = '3a87be158f3115dd426d34c8f1f3c52fa537d85fe413db831c486d1bb07dc290';

test('verifier hashes the canonical reference input to the cross-language reference hash', () => {
  assert.equal(sha256MigrationHex(REFERENCE_INPUT_CANONICAL), REFERENCE_HASH);
});

test('verifier collapses trim + line-ending differences into one hash (#2972 regression)', () => {
  // Two "test files" that differ only in trailing whitespace, leading
  // whitespace, line-ending convention, and an optional BOM. The
  // verifier MUST hash all of them to the same digest as the canonical
  // input — otherwise the runtime's normalization (which IS lossy on
  // these dimensions) would diverge from the verifier and we'd
  // re-introduce the #2162/#2605 nuclear-recovery trap.
  const fileA = 'CREATE TABLE t (id INTEGER);\n';
  const fileB = '  CREATE TABLE t (id INTEGER);  \r\n';
  const fileC = '\u{feff}CREATE TABLE t (id INTEGER);';
  const fileD = '\r\nCREATE TABLE t (id INTEGER);\r\n\r\n   ';

  for (const variant of [fileA, fileB, fileC, fileD]) {
    assert.equal(normalizeMigrationSql(variant), REFERENCE_INPUT_CANONICAL);
    assert.equal(sha256MigrationHex(variant), REFERENCE_HASH);
  }
});

test('verifier preserves interior whitespace so DDL edits cannot slip past the lock', () => {
  // The whole point of normalization is to ignore edge / line-ending
  // noise WITHOUT letting semantic SQL changes reformat their way past
  // the `ChecksumMismatch` runtime guard.
  const tightSpacing = 'SELECT 1;';
  const looseSpacing = 'SELECT  1;';
  assert.notEqual(sha256MigrationHex(tightSpacing), sha256MigrationHex(looseSpacing));
});

test('verifier strips line + block comments (audit #3021-bonus)', () => {
  // Comment-only edits to a frozen migration must NOT trip
  // `ChecksumMismatch`. Both `--` line comments and `/* *\/` block
  // comments are semantic-preserving (SQLite ignores them), so a
  // comment reflow / audit-note rewrite should not require a
  // checksum-lock regeneration. Mirrors the Rust regression tests in
  // `migration::checksum::tests::strips_*_comments_before_hashing`.
  const withLine = '-- audit note\nCREATE TABLE t (id INTEGER); -- inline\n';
  const withBlock = '/* audit note */ CREATE TABLE t (id INTEGER); /* trailing */';
  const withoutLine = 'CREATE TABLE t (id INTEGER); ';
  const withoutBlock = ' CREATE TABLE t (id INTEGER); ';
  assert.equal(sha256MigrationHex(withLine), sha256MigrationHex(withoutLine));
  assert.equal(sha256MigrationHex(withBlock), sha256MigrationHex(withoutBlock));
});

test('verifier preserves comment-looking text inside string literals', () => {
  // `--` inside a `'...'` literal is NOT a comment at the SQL parser
  // level. Stripping it would silently collapse two semantically-
  // distinct migrations into the same hash.
  const withLiteral = "INSERT INTO t VALUES ('-- not a comment');";
  const withoutLiteral = "INSERT INTO t VALUES ('');";
  assert.notEqual(sha256MigrationHex(withLiteral), sha256MigrationHex(withoutLiteral));
});

test('comment block line count does not drift hash (#3274)', () => {
  // Pre-fix, the strip pass left one blank line per stripped comment
  // line, so a 5-line comment block and a 7-line block normalized to
  // different byte sequences and hashed differently. Every doc-rot
  // sweep that reflowed comments in `001_schema.sql` required a lock
  // regeneration. Mirrors `comment_block_line_count_does_not_drift_hash`.
  const fiveLine = [
    'CREATE TABLE a (id INTEGER);',
    '-- comment line 1',
    '-- comment line 2',
    '-- comment line 3',
    '-- comment line 4',
    '-- comment line 5',
    'CREATE TABLE b (id INTEGER);',
    '',
  ].join('\n');
  const sevenLine = [
    'CREATE TABLE a (id INTEGER);',
    '-- comment line 1',
    '-- comment line 2',
    '-- comment line 3',
    '-- comment line 4',
    '-- comment line 5',
    '-- comment line 6',
    '-- comment line 7',
    'CREATE TABLE b (id INTEGER);',
    '',
  ].join('\n');
  const oneLine = [
    'CREATE TABLE a (id INTEGER);',
    '-- comment compressed to a single line',
    'CREATE TABLE b (id INTEGER);',
    '',
  ].join('\n');
  const noComment = 'CREATE TABLE a (id INTEGER);\nCREATE TABLE b (id INTEGER);\n';
  const h = sha256MigrationHex(noComment);
  assert.equal(sha256MigrationHex(fiveLine), h);
  assert.equal(sha256MigrationHex(sevenLine), h);
  assert.equal(sha256MigrationHex(oneLine), h);
});

test('block comment internal layout does not drift hash (#3274)', () => {
  const singleLine = 'CREATE TABLE a;\n/* short note */\nCREATE TABLE b;\n';
  const multiLine = [
    'CREATE TABLE a;',
    '/*',
    ' * multi',
    ' * line',
    ' * note',
    ' */',
    'CREATE TABLE b;',
    '',
  ].join('\n');
  const noComment = 'CREATE TABLE a;\nCREATE TABLE b;\n';
  const h = sha256MigrationHex(noComment);
  assert.equal(sha256MigrationHex(singleLine), h);
  assert.equal(sha256MigrationHex(multiLine), h);
});

test('inline comment trailing whitespace does not drift hash (#3274)', () => {
  const withInline = 'CREATE TABLE t (id INTEGER);   -- trailing\n';
  const bare = 'CREATE TABLE t (id INTEGER);\n';
  assert.equal(sha256MigrationHex(withInline), sha256MigrationHex(bare));
});

test('blank lines between statements do not drift hash (#3274)', () => {
  const tight = 'CREATE TABLE a;\nCREATE TABLE b;\n';
  const loose = 'CREATE TABLE a;\n\n\n\nCREATE TABLE b;\n';
  assert.equal(sha256MigrationHex(tight), sha256MigrationHex(loose));
});

test('multi-line string literals keep embedded newlines (#3274)', () => {
  // Embedded newlines inside a literal are semantically meaningful
  // (they end up in the inserted row), so the strip pass must NOT
  // collapse them — they're not comment-induced whitespace.
  const literalA = "INSERT INTO t VALUES ('first\nsecond');";
  const literalB = "INSERT INTO t VALUES ('first second');";
  assert.notEqual(sha256MigrationHex(literalA), sha256MigrationHex(literalB));

  // Reflowing code-state blank lines around a multi-line literal
  // must still hash to the same digest as the bare statement.
  const withBlanks = "\n\nINSERT INTO t VALUES ('first\nsecond');\n\n";
  const bare = "INSERT INTO t VALUES ('first\nsecond');";
  assert.equal(sha256MigrationHex(withBlanks), sha256MigrationHex(bare));
});
