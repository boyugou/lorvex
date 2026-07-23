use super::*;

#[test]
fn deterministic() {
    let sql = "CREATE TABLE t (id INTEGER PRIMARY KEY);";
    assert_eq!(sha256_hex(sql), sha256_hex(sql));
}

#[test]
fn ignores_surrounding_whitespace() {
    let a = "  SELECT 1;  \n";
    let b = "SELECT 1;";
    assert_eq!(sha256_hex(a), sha256_hex(b));
}

#[test]
fn ignores_line_ending_differences() {
    // a Windows clone with `core.autocrlf=true`
    // rewrites every LF to CRLF on checkout. The pre-fix hash
    // differed from the Unix-cloned hash, tripping
    // ChecksumMismatch on first launch and triggering the nuclear
    // DB-backup-then-delete recovery path. Normalize CRLF → LF so
    // the hash is line-ending-agnostic.
    let unix = "CREATE TABLE t (id INTEGER);\nINSERT INTO t VALUES (1);";
    let windows = "CREATE TABLE t (id INTEGER);\r\nINSERT INTO t VALUES (1);";
    assert_eq!(sha256_hex(unix), sha256_hex(windows));
}

#[test]
fn ignores_utf8_bom() {
    let with_bom = "\u{feff}SELECT 1;";
    let without = "SELECT 1;";
    assert_eq!(sha256_hex(with_bom), sha256_hex(without));
}

#[test]
fn interior_whitespace_still_matters() {
    // Interior SQL semantics must still affect the hash — we only
    // normalize edge/line-ending noise.
    let a = "SELECT 1;";
    let b = "SELECT  1;"; // two spaces between SELECT and 1
    assert_ne!(sha256_hex(a), sha256_hex(b));
}

#[test]
fn different_content_different_hash() {
    assert_ne!(sha256_hex("SELECT 1;"), sha256_hex("SELECT 2;"));
}

/// comment-only edits to a frozen migration
/// must NOT trip `ChecksumMismatch`. Prior to this fix, every
/// audit note added (or moved, or reflowed) to `001_schema.sql`
/// drifted the on-disk hash, requiring a `checksums.lock`
/// regeneration that masked the change as a "real" migration
/// edit. Strip both `-- line` and `/* block */` comments before
/// hashing so semantically-identical SQL with different comments
/// hashes to the same digest.
#[test]
fn strips_line_comments_before_hashing() {
    let with = "-- audit note\nCREATE TABLE t (id INTEGER); -- inline\n";
    let without = "CREATE TABLE t (id INTEGER); ";
    assert_eq!(sha256_hex(with), sha256_hex(without));
}

#[test]
fn strips_block_comments_before_hashing() {
    let with = "/* audit note */ CREATE TABLE t (id INTEGER); /* trailing */";
    let without = " CREATE TABLE t (id INTEGER); ";
    assert_eq!(sha256_hex(with), sha256_hex(without));
}

/// #3274 regression: rewording a comment to span a different
/// number of lines must not drift the hash. Before the fix the
/// strip pass left blank lines behind (one per stripped comment
/// line), and a 5-line comment block produced a different
/// normalized output than a 7-line one — every doc-rot sweep
/// touching `001_schema.sql` required regenerating the lock.
#[test]
fn comment_block_line_count_does_not_drift_hash() {
    let five_line = "\
CREATE TABLE a (id INTEGER);
-- comment line 1
-- comment line 2
-- comment line 3
-- comment line 4
-- comment line 5
CREATE TABLE b (id INTEGER);
";
    let seven_line = "\
CREATE TABLE a (id INTEGER);
-- comment line 1
-- comment line 2
-- comment line 3
-- comment line 4
-- comment line 5
-- comment line 6
-- comment line 7
CREATE TABLE b (id INTEGER);
";
    let one_line = "\
CREATE TABLE a (id INTEGER);
-- comment compressed to a single line
CREATE TABLE b (id INTEGER);
";
    let no_comment = "\
CREATE TABLE a (id INTEGER);
CREATE TABLE b (id INTEGER);
";
    let h = sha256_hex(no_comment);
    assert_eq!(sha256_hex(five_line), h);
    assert_eq!(sha256_hex(seven_line), h);
    assert_eq!(sha256_hex(one_line), h);
}

/// #3274: block comments spanning a variable number of lines
/// must hash equal regardless of internal layout.
#[test]
fn block_comment_internal_layout_does_not_drift_hash() {
    let single_line = "CREATE TABLE a;\n/* short note */\nCREATE TABLE b;\n";
    let multi_line = "\
CREATE TABLE a;
/*
 * multi
 * line
 * note
 */
CREATE TABLE b;
";
    let no_comment = "CREATE TABLE a;\nCREATE TABLE b;\n";
    let h = sha256_hex(no_comment);
    assert_eq!(sha256_hex(single_line), h);
    assert_eq!(sha256_hex(multi_line), h);
}

/// #3274: an inline `-- comment` at end of a code line must not
/// leak the pre-comment whitespace into the hash. The two inputs
/// below are semantically identical (SQLite ignores the comment
/// AND the trailing whitespace) but the pre-fix implementation
/// hashed them differently because the trailing `   ` survived.
#[test]
fn inline_comment_trailing_whitespace_does_not_drift_hash() {
    let with_inline = "CREATE TABLE t (id INTEGER);   -- trailing\n";
    let bare = "CREATE TABLE t (id INTEGER);\n";
    assert_eq!(sha256_hex(with_inline), sha256_hex(bare));
}

/// #3274 boundary check: blank lines (with or without surrounding
/// comments) between code blocks are noise that must not affect
/// the hash. This is the strongest form of the comment-only-edit
/// invariant — it also covers "I added some breathing room around
/// these statements" non-comment formatting edits, which are
/// equivalently semantic-preserving.
#[test]
fn blank_lines_between_statements_do_not_drift_hash() {
    let tight = "CREATE TABLE a;\nCREATE TABLE b;\n";
    let loose = "CREATE TABLE a;\n\n\n\nCREATE TABLE b;\n";
    assert_eq!(sha256_hex(tight), sha256_hex(loose));
}

/// #3274: a multi-line string literal must NOT have its embedded
/// newlines collapsed by the comment-strip pass. The embedded
/// blank line below is part of the literal's stored value, not
/// noise from comment removal.
#[test]
fn multi_line_string_literals_keep_embedded_newlines() {
    let literal_a = "INSERT INTO t VALUES ('first\nsecond');";
    let literal_b = "INSERT INTO t VALUES ('first second');";
    assert_ne!(
        sha256_hex(literal_a),
        sha256_hex(literal_b),
        "embedded newline inside a literal is semantically distinct from a space"
    );

    // And reflowing/adding code-state blank lines next to a
    // multi-line literal must still hash equal to the same code
    // without the blank lines — the literal is preserved verbatim
    // either way.
    let with_blanks = "\n\nINSERT INTO t VALUES ('first\nsecond');\n\n";
    let bare = "INSERT INTO t VALUES ('first\nsecond');";
    assert_eq!(sha256_hex(with_blanks), sha256_hex(bare));
}

/// Sanity guard: a `-- comment` inside a string literal is NOT a
/// SQL comment. The strip pass must leave it intact, otherwise it
/// would silently collide with a different literal.
#[test]
fn line_comment_inside_literal_is_not_stripped() {
    let with = "INSERT INTO t VALUES ('value -- not a comment');";
    let without = "INSERT INTO t VALUES ('value ');";
    assert_ne!(sha256_hex(with), sha256_hex(without));
}

#[test]
fn comment_strip_preserves_string_literals() {
    // `--` and `/*` inside a quoted run are NOT comments — the
    // SQL parser reads them as literal text. The hash must reflect
    // that; otherwise a migration that deliberately encodes a
    // comment-looking string would silently collide with a
    // semantically-different one.
    let with_literal_comment_marker = "INSERT INTO t VALUES ('-- not a comment');";
    let stripped_visually = "INSERT INTO t VALUES ('');";
    assert_ne!(
        sha256_hex(with_literal_comment_marker),
        sha256_hex(stripped_visually),
        "comment strip must NOT touch quoted string literals"
    );
}

#[test]
fn semantic_edits_still_change_hash() {
    // Comment-only edits should be invisible, but a genuine SQL
    // change (renaming a column, swapping a constraint) must still
    // produce a new hash even when wrapped in identical comments.
    let a = "-- header\nCREATE TABLE t (id INTEGER PRIMARY KEY);";
    let b = "-- header\nCREATE TABLE t (id BLOB PRIMARY KEY);";
    assert_ne!(sha256_hex(a), sha256_hex(b));
}

/// Cross-language parity contract — see issue #2972.
///
/// `sha256_hex` (this runtime) and the verifier helper
/// `sha256MigrationHex` in `scripts/verify/migration_checksums.mjs`
/// MUST hash the same SQL text to the same hex digest. Until #2972
/// they drifted: the runtime trimmed + LF-normalized + BOM-stripped
/// before hashing while the verifier hashed raw bytes. The Node
/// counterpart of this test lives in
/// `scripts/tests/runtime/migration_checksum_parity.test.mjs` and
/// asserts the SAME `REFERENCE_HASH` for variants of the same
/// canonical input. If you change either constant you MUST change
/// both — they are how we keep the two implementations from
/// drifting again.
#[test]
fn parity_with_verifier_reference_hash() {
    const REFERENCE_INPUT_CANONICAL: &str = "CREATE TABLE t (id INTEGER);";
    const REFERENCE_HASH: &str = "3a87be158f3115dd426d34c8f1f3c52fa537d85fe413db831c486d1bb07dc290";

    // Variants the runtime+verifier MUST collapse to the same hash:
    // trailing whitespace, leading whitespace, CRLF, optional BOM —
    // the same set the verifier's regression test exercises.
    let variants = [
        "CREATE TABLE t (id INTEGER);\n",
        "  CREATE TABLE t (id INTEGER);  \r\n",
        "\u{feff}CREATE TABLE t (id INTEGER);",
        "\r\nCREATE TABLE t (id INTEGER);\r\n\r\n   ",
    ];

    assert_eq!(sha256_hex(REFERENCE_INPUT_CANONICAL), REFERENCE_HASH);
    for raw in variants {
        assert_eq!(
            sha256_hex(raw),
            REFERENCE_HASH,
            "runtime hash drifted from cross-language reference for variant: {raw:?}"
        );
    }
}
