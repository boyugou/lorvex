use sha2::{Digest, Sha256};

/// Compute a hex-encoded SHA-256 checksum of a migration's SQL text.
///
/// Normalization before hashing:
///   * strip a UTF-8 BOM if present
///   * replace CRLF with LF so Windows clones with `core.autocrlf=true`
///     don't produce a different hash than a Unix clone of the same
///     migration file — without normalization the hash would trip
///     `ChecksumMismatch` on every migration on first launch, which
///     the app handles by backing up + deleting the DB (nuclear
///     recovery)
///   * strip SQL comments (`-- line` and `/* block */`) AND drop any
///     line that becomes whitespace-only as a result, AND drop the
///     trailing whitespace before an inline comment. This makes the
///     "semantic-preserving comment-only edit" guarantee actually hold
///     end-to-end: reflowing a 5-line comment into 7 lines, or moving
///     an inline comment without changing the surrounding code, both
///     hash to the same digest. See issue #3274 for the regression
///     this replaces.
///   * trim leading/trailing whitespace so an editor that adds a final
///     newline (or strips one) doesn't invalidate a frozen migration
///
/// We do NOT collapse interior whitespace inside non-comment SQL — that
/// would hide real edits that change the DDL. We only collapse
/// whitespace produced by removing comments.
pub fn sha256_hex(sql: &str) -> String {
    let mut normalized = sql;
    if let Some(stripped) = normalized.strip_prefix('\u{feff}') {
        normalized = stripped;
    }
    let normalized = normalized.replace("\r\n", "\n");
    let stripped = strip_sql_comments(&normalized);
    let trimmed = stripped.trim();
    let mut hasher = Sha256::new();
    hasher.update(trimmed.as_bytes());
    hex::encode(hasher.finalize())
}

/// Strip SQL comments (`-- line` and `/* block */`) while preserving
/// string literals and identifiers.
///
/// Per-line buffering: each input line accumulates into `pending` until
/// a newline (outside any literal) flushes it. A line that contains no
/// non-whitespace content after comment removal is dropped entirely —
/// including its trailing newline — so a 5-line comment block and a
/// 7-line comment block reduce to the same output. Inline comments
/// also trim the trailing whitespace they leave behind on the
/// surviving line, so `"X; -- inline\n"` and `"X;\n"` hash equal.
///
/// String literals (single quotes) and quoted identifiers (double
/// quotes) pass through verbatim, including embedded newlines and
/// embedded `--` / `/*` markers (those are NOT comments at the SQL
/// parser level). SQLite-style escaped quotes (`''` / `""`) keep the
/// quoted run open. Block comments do not nest in SQLite; an
/// unterminated block runs to end-of-input.
fn strip_sql_comments(sql: &str) -> String {
    // We walk byte indices because every structural token (`'`, `"`,
    // `-`, `/`, `*`, `\n`) is ASCII, so byte-level look-ahead is safe
    // and avoids the upfront `Vec<char>` allocation. Multi-byte UTF-8
    // characters in literals or identifiers are copied as whole-char
    // substrings using `utf8_char_len`.
    let bytes = sql.as_bytes();
    let mut out = String::with_capacity(sql.len());
    let mut pending = String::new();
    let mut pending_has_content = false;
    let mut i = 0;

    while i < bytes.len() {
        let b = bytes[i];

        if b == b'\n' {
            // End of a Code line. Whitespace-only lines (which is what
            // a removed comment produces) are dropped including the
            // newline; lines with content flush as `pending + '\n'`.
            if pending_has_content {
                out.push_str(&pending);
                out.push('\n');
            }
            pending.clear();
            pending_has_content = false;
            i += 1;
            continue;
        }

        if b == b'\'' {
            pending.push('\'');
            pending_has_content = true;
            i += 1;
            // Verbatim copy until the closing quote. Embedded `\n` is
            // legal SQL inside a literal and must survive — it is part
            // of the literal's stored value, not a Code-state line
            // break.
            while i < bytes.len() {
                if bytes[i] == b'\'' {
                    pending.push('\'');
                    i += 1;
                    // SQLite escape: `''` = a single quote inside the
                    // literal, the run continues.
                    if i < bytes.len() && bytes[i] == b'\'' {
                        pending.push('\'');
                        i += 1;
                        continue;
                    }
                    break;
                }
                let ch_len = utf8_char_len(bytes[i]);
                let end = (i + ch_len).min(bytes.len());
                pending.push_str(&sql[i..end]);
                i = end;
            }
            continue;
        }

        if b == b'"' {
            pending.push('"');
            pending_has_content = true;
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'"' {
                    pending.push('"');
                    i += 1;
                    if i < bytes.len() && bytes[i] == b'"' {
                        pending.push('"');
                        i += 1;
                        continue;
                    }
                    break;
                }
                let ch_len = utf8_char_len(bytes[i]);
                let end = (i + ch_len).min(bytes.len());
                pending.push_str(&sql[i..end]);
                i = end;
            }
            continue;
        }

        if b == b'-' && i + 1 < bytes.len() && bytes[i + 1] == b'-' {
            // Line comment. Trim any trailing whitespace pre-comment
            // so an inline comment doesn't leak `"X;   "` into the
            // hash. The newline (if any) is left for the outer loop;
            // if the line ends up whitespace-only it will be dropped.
            trim_trailing_whitespace(&mut pending, &mut pending_has_content);
            i += 2;
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            continue;
        }

        if b == b'/' && i + 1 < bytes.len() && bytes[i + 1] == b'*' {
            // Block comment — same trim rule. Block comments may span
            // multiple lines; we consume the entire span, so any
            // newlines inside the comment vanish along with the rest.
            trim_trailing_whitespace(&mut pending, &mut pending_has_content);
            i += 2;
            while i + 1 < bytes.len() && !(bytes[i] == b'*' && bytes[i + 1] == b'/') {
                i += 1;
            }
            if i + 1 < bytes.len() {
                i += 2;
            } else {
                i = bytes.len();
            }
            continue;
        }

        // Regular Code-state byte: copy one whole UTF-8 char.
        let ch_len = utf8_char_len(b);
        let end = (i + ch_len).min(bytes.len());
        let chunk = &sql[i..end];
        pending.push_str(chunk);
        if !chunk.chars().all(char::is_whitespace) {
            pending_has_content = true;
        }
        i = end;
    }

    // Trailing partial line (no terminator).
    if pending_has_content {
        out.push_str(&pending);
    }
    out
}

#[inline]
// The 0x00..=0x7F arm and the wildcard "invalid lead byte" arm both
// return 1, but they encode different intents (ASCII vs. defensive
// progress on malformed input). Keep them separate so the UTF-8 spec
// is documented exhaustively in the match.
#[allow(clippy::match_same_arms)]
const fn utf8_char_len(first_byte: u8) -> usize {
    match first_byte {
        0x00..=0x7F => 1,
        0xC0..=0xDF => 2,
        0xE0..=0xEF => 3,
        0xF0..=0xF7 => 4,
        // Invalid UTF-8 lead byte. Advance one to make progress; the
        // input must already have been validated as `&str` so this
        // branch is unreachable in practice.
        _ => 1,
    }
}

#[inline]
fn trim_trailing_whitespace(pending: &mut String, has_content: &mut bool) {
    let trimmed_len = pending.trim_end().len();
    pending.truncate(trimmed_len);
    if pending.is_empty() {
        *has_content = false;
    }
}

#[cfg(test)]
mod tests;
