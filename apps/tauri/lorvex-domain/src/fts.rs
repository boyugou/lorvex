const MAX_FTS_TOKENS: usize = 64;
/// Hard cap on per-token character count. Tokens longer than this are
/// truncated before being quoted into the FTS5 MATCH string or the LIKE
/// fallback. Without this, a single 10k-char whitespace-
/// less blob passed through as one "token" and produced a pathological
/// LIKE full-scan. 64 chars is more than any legitimate search term.
const MAX_FTS_TOKEN_CHARS: usize = 64;
/// Hard cap on the raw query character count before tokenization. Any
/// input longer than this is truncated at a char boundary. Belt-and-
/// suspenders alongside MAX_FTS_TOKEN_CHARS — callers that paste a
/// giant blob shouldn't even reach tokenization.
pub(crate) const MAX_FTS_QUERY_CHARS: usize = 512;

/// Truncate `query` to at most `MAX_FTS_QUERY_CHARS` chars, respecting
/// Unicode char boundaries. Callers should apply this before any
/// downstream query planning (FTS MATCH or LIKE fallback).
pub fn cap_fts_query_length(query: &str) -> &str {
    match query.char_indices().nth(MAX_FTS_QUERY_CHARS) {
        Some((idx, _)) => &query[..idx],
        None => query,
    }
}

/// Returns true if `query` should skip FTS5 entirely and go straight to
/// the LIKE fallback path. This catches queries that FTS5's `unicode61`
/// tokenizer would reduce to zero tokens — which makes FTS5 either
/// return no rows silently or throw a parse error that the caller then
/// has to string-match on. We replace both the
/// "CJK-detect" shortcut and the error-triggered fallback with a single
/// up-front test so the contract is explicit.
///
/// Fallback is required when the query contains:
/// - CJK characters (unicode61 treats CJK as opaque tokens)
/// - No alphanumeric characters at all (emoji-only, punctuation-only,
///   symbol-only — unicode61 would emit zero tokens)
pub fn should_use_like_fallback(query: &str) -> bool {
    if contains_cjk(query) {
        return true;
    }
    // If there is no alphanumeric character anywhere in the input, the
    // unicode61 tokenizer would tokenize the whole query as nothing and
    // FTS5 would throw. Do the substring search directly.
    !query.chars().any(char::is_alphanumeric)
}

/// Minimum length for a bare trailing token to be considered "long enough"
/// to rely on FTS5 prefix matching alone. Below this (2–3 char tokens),
/// the prefix wildcard still requires the token to appear at the start of
/// an indexed word, so `oject` cannot hit `project-alpha`.
/// the caller should retry via `LIKE %token%` when the FTS query for such
/// a short trailing token returns zero rows.
const SHORT_TOKEN_MAX_LEN: usize = 3;

/// Returns `Some(tok)` when the input's *trailing* bare token is short
/// enough (2–3 chars, ASCII alphanumeric) that the caller should plan a
/// `LIKE %tok%` retry in case FTS5 prefix-matching produces zero rows.
/// Returns `None` for longer trailing tokens, for quoted-phrase trailers,
/// for email-like trailers (which already become phrases), or when the
/// query has no alphanumeric trailing run at all.
///
/// FTS5 prefix wildcards (`tok*`) only match the *start* of
/// indexed words, so `oject*` does not hit a task titled "project-alpha"
/// even though the user clearly intended a substring search. The retry
/// path is the LIKE scan, which already exists; this helper just lets
/// the search command know which queries are candidates for retry.
pub fn short_trailing_token_for_like_retry(query: &str) -> Option<&str> {
    // Walk back from the end, skipping any trailing whitespace. If the
    // trailer is enclosed in a `"..."` phrase we bail — the user was
    // explicit about phrase intent. If the trailer contains `@` or `.`
    // we also bail because it would have been emitted as a phrase by
    // `sanitize_fts_query`; retrying on just the last dotted segment
    // would be misleading.
    let trimmed = query.trim_end();
    if trimmed.is_empty() || trimmed.ends_with('"') {
        return None;
    }
    // Locate the byte offset where the trailing alphanumeric run
    // starts by walking `char_indices` in reverse and stopping at the
    // first non-alphanumeric.
    // reversed chars into a `Vec<char>`, then re-reversed and `collect`-ed
    // into a `String` — two heap allocations per FTS retry probe — when
    // a borrowed slice into the original `&str` was already sufficient.
    let trailing_start = trimmed
        .char_indices()
        .rev()
        .find(|(_, c)| !c.is_alphanumeric())
        .map_or(0, |(idx, c)| idx + c.len_utf8());
    let trailing = &trimmed[trailing_start..];
    if trailing.is_empty() {
        return None;
    }
    // The char immediately before the trailing run decides whether
    // the user was typing an email/dotted token. Only `@` or `.`
    // immediately preceding the trailing run disqualifies retry — any
    // other non-alphanumeric (space, hyphen, etc.) is fine.
    if let Some(prev) = trimmed[..trailing_start].chars().next_back() {
        if prev == '@' || prev == '.' {
            return None;
        }
    }
    let char_count = trailing.chars().count();
    (2..=SHORT_TOKEN_MAX_LEN)
        .contains(&char_count)
        .then_some(trailing)
}

/// Returns `true` if the query contains any CJK (Chinese/Japanese/Korean) characters.
///
/// FTS5's default `unicode61` tokenizer treats CJK text as single opaque tokens
/// because it splits only on whitespace and punctuation. A search for `中文` won't
/// match a task titled `写一个中文任务` via FTS5 MATCH, because the entire string
/// is one token. Callers should use a LIKE fallback for queries that contain CJK.
pub fn contains_cjk(query: &str) -> bool {
    query.chars().any(|c| {
        matches!(c,
            '\u{4E00}'..='\u{9FFF}'   // CJK Unified Ideographs
            | '\u{3400}'..='\u{4DBF}' // CJK Extension A
            | '\u{20000}'..='\u{2A6DF}' // CJK Extension B
            | '\u{3040}'..='\u{309F}' // Hiragana
            | '\u{30A0}'..='\u{30FF}' // Katakana
            | '\u{31F0}'..='\u{31FF}' // Katakana Phonetic Extensions
            | '\u{AC00}'..='\u{D7AF}' // Korean Hangul Syllables
            | '\u{1100}'..='\u{11FF}' // Hangul Jamo
            | '\u{FF65}'..='\u{FF9F}' // Halfwidth Katakana
            | '\u{F900}'..='\u{FAFF}' // CJK Compatibility Ideographs
        )
    })
}

/// A single unit of FTS query output after sanitization.
///
/// - `Word` — a single alphanumeric token. Rendered as `"word"` (exact)
///   or `"word"*` (prefix) by the final joiner.
/// - `Phrase` — an ordered multi-word FTS5 phrase. Rendered as
///   `"w1 w2 w3"` or `"w1 w2 w3"*` (the `*` makes the final word a
///   prefix). Emitted for quoted user input (`"exact phrase"`) and for
///   email-/dot-separated identifier runs like `alice@example.com`.
#[derive(Debug, Clone, PartialEq, Eq)]
enum FtsUnit {
    Word(String),
    Phrase(Vec<String>),
}

impl FtsUnit {
    fn is_empty(&self) -> bool {
        match self {
            FtsUnit::Word(w) => w.is_empty(),
            FtsUnit::Phrase(words) => words.is_empty() || words.iter().all(String::is_empty),
        }
    }

    /// Append this unit's rendered FTS5 form directly into `out`.
    ///
    /// each unit allocated its own
    /// `String` via `format!` and the caller collected them into a
    /// `Vec<String>` to `join(" ")`. On the per-keystroke search
    /// path that was 1 `String` per unit + 1 `Vec<String>` + the
    /// final join allocation. Streaming into the caller's
    /// accumulator drops the per-unit allocation and the
    /// intermediate vec.
    fn write_to(&self, out: &mut String, is_last: bool) {
        match self {
            FtsUnit::Word(w) => {
                out.push('"');
                out.push_str(w);
                out.push('"');
            }
            FtsUnit::Phrase(words) => {
                out.push('"');
                let mut first = true;
                for word in words {
                    if !first {
                        out.push(' ');
                    }
                    out.push_str(word);
                    first = false;
                }
                out.push('"');
            }
        }
        if is_last {
            out.push('*');
        }
    }
}

/// Clean a raw token fragment by stripping FTS5-syntactic characters
/// and control chars, truncating to `MAX_FTS_TOKEN_CHARS`. Returns an
/// empty string if nothing survives.
fn clean_token(token: &str) -> String {
    token
        .chars()
        .filter(|ch| {
            !matches!(ch, '"' | '*' | '(' | ')' | ':' | '^' | '{' | '}') && !ch.is_control()
        })
        .take(MAX_FTS_TOKEN_CHARS)
        .collect()
}

/// Split a bare (unquoted) whitespace-delimited token into `FtsUnit`s.
///
/// Heuristic (issue #2719): if the token contains an internal `@` or `.`
/// and at least two alphanumeric runs separated by such a delimiter, we
/// preserve ordering by emitting a single `Phrase` unit. This covers
/// emails (`alice@example.com`) and dotted identifiers (`v1.2.3`)
/// without re-introducing the "2024-Q1 forces ordered adjacency of
/// 2024 then Q1" pitfall from that one had no `@` or `.`
/// and still splits into AND-combined subtokens.
///
/// Otherwise the token is split on every non-alphanumeric character and
/// each run becomes its own `Word` unit (the existing behaviour).
// trust: `.next().unwrap()` on a single-element Vec is provably Some —
// guarded by the `cleaned_runs.len() == 1` branch above.
#[allow(clippy::unwrap_used)]
fn split_bare_token(token: &str) -> Vec<FtsUnit> {
    // Borrow the runs as `&str` slices into `token`; the downstream
    // `clean_token` already takes `&str` and returns its own owned
    // every run was redundant — one `String` allocation per run on
    // every search keystroke is a real cost when the user types a
    // long unstructured phrase.
    let runs: Vec<&str> = token
        .split(|c: char| !c.is_alphanumeric())
        .filter(|s| !s.is_empty())
        .collect();
    if runs.len() < 2 {
        return runs
            .into_iter()
            .map(|r| FtsUnit::Word(clean_token(r)))
            .filter(|u| !u.is_empty())
            .collect();
    }
    let is_identifier_like =
        token.chars().any(|c| c == '@' || c == '.') && !token.chars().any(char::is_whitespace);
    if is_identifier_like {
        let cleaned_runs: Vec<String> = runs
            .iter()
            .map(|r| clean_token(r))
            .filter(|r| !r.is_empty())
            .collect();
        if cleaned_runs.len() >= 2 {
            return vec![FtsUnit::Phrase(cleaned_runs)];
        } else if cleaned_runs.len() == 1 {
            return vec![FtsUnit::Word(cleaned_runs.into_iter().next().unwrap())];
        }
        return Vec::new();
    }
    runs.into_iter()
        .map(|r| FtsUnit::Word(clean_token(r)))
        .filter(|u| !u.is_empty())
        .collect()
}

/// Parse input into a stream of raw segments: either `Quoted(raw)` for
/// content inside a `"..."` span, or `Bare(raw)` for whitespace-
/// delimited runs outside any quoted span. An unterminated opening
/// quote is treated as if the quote closed at end-of-input so typed-
/// ahead `foo "bar` still produces usable output.
fn split_segments(input: &str) -> Vec<Segment<'_>> {
    let mut segments = Vec::new();
    let mut rest = input;
    loop {
        // Skip leading whitespace between segments.
        rest = rest.trim_start();
        if rest.is_empty() {
            break;
        }
        if let Some(stripped) = rest.strip_prefix('"') {
            // Quoted span: take until the next `"` or end-of-input.
            let (inside, tail) = stripped.find('"').map_or((stripped, ""), |idx| {
                (&stripped[..idx], &stripped[idx + 1..])
            });
            segments.push(Segment::Quoted(inside));
            rest = tail;
        } else {
            // Bare run: take up to the next whitespace or `"`.
            let end = rest
                .char_indices()
                .find(|(_, c)| c.is_whitespace() || *c == '"')
                .map_or(rest.len(), |(i, _)| i);
            let (bare, tail) = rest.split_at(end);
            if !bare.is_empty() {
                segments.push(Segment::Bare(bare));
            }
            rest = tail;
        }
    }
    segments
}

#[derive(Debug)]
enum Segment<'a> {
    Bare(&'a str),
    Quoted(&'a str),
}

/// Sanitize a user query for FTS5 MATCH syntax.
///
/// Splits the input into whitespace-separated tokens and wraps each in
/// double quotes so they are treated as literal phrases. Tokens are
/// implicitly ANDed by FTS5 when separated by spaces. Characters with
/// special meaning in FTS5 query syntax are stripped, and control
/// characters are removed before quoting.
///
///
/// - `"exact phrase"` in the raw input is preserved as a single FTS5
///   phrase `"exact phrase"`, not stripped and reduced to AND-combined
///   words. This gives users an explicit way to force ordered matching.
/// - Identifier-like tokens containing `@` or `.` (email addresses,
///   dotted names) are emitted as a single phrase `"alice example com"`
///   so FTS5 matches the component tokens in order. Indexed text like
///   "Contact alice@example.com" tokenizes to `[contact, alice,
///   example, com]` and the phrase matches the ordered subrun. A
///   naive AND split `"alice" AND "example" AND "com"` would also
///   match `"see example.com then ping alice"` — a false positive.
// trust: `.next().unwrap()` is guarded by the `words.len() == 1` match arm
// above — provably Some.
#[allow(clippy::unwrap_used)]
pub fn sanitize_fts_query(input: &str) -> String {
    // Truncate the raw input before tokenization so a 10k-char blob
    // never reaches the FTS5 engine or the LIKE fallback.
    let input = cap_fts_query_length(input);

    let mut units: Vec<FtsUnit> = Vec::new();
    for segment in split_segments(input) {
        if units.len() >= MAX_FTS_TOKENS {
            break;
        }
        match segment {
            Segment::Quoted(raw) => {
                // Inside quotes: collect all alphanumeric runs as the
                // phrase's words. We deliberately don't split on `@`
                // or `.` differently — the user's explicit intent is
                // "these words in this order", so any non-alnum
                // separator produces an ordered phrase.
                let words: Vec<String> = raw
                    .split(|c: char| !c.is_alphanumeric())
                    .map(clean_token)
                    .filter(|s| !s.is_empty())
                    .collect();
                match words.len() {
                    0 => {}
                    1 => units.push(FtsUnit::Word(words.into_iter().next().unwrap())),
                    _ => units.push(FtsUnit::Phrase(words)),
                }
            }
            Segment::Bare(raw) => {
                for unit in split_bare_token(raw) {
                    if unit.is_empty() {
                        continue;
                    }
                    units.push(unit);
                    if units.len() >= MAX_FTS_TOKENS {
                        break;
                    }
                }
            }
        }
    }

    if units.is_empty() {
        return String::new();
    }

    units.truncate(MAX_FTS_TOKENS);

    // All units except the last render unwildcarded; the last gets a
    // prefix wildcard (`*`). For phrases, `*` applies to the final
    // word in the phrase per FTS5's "phrase" + prefix semantics.
    //
    // Stream every unit directly into a single accumulator instead of
    // collecting a `Vec<String>` of per-unit renders to `.join(" ")`.
    // see `FtsUnit::write_to` for rationale — the previous
    // shape allocated per unit on every keystroke.
    let last = units.len() - 1;
    let mut out = String::with_capacity(input.len() + 8);
    for (i, unit) in units.iter().enumerate() {
        if i > 0 {
            out.push(' ');
        }
        unit.write_to(&mut out, i == last);
    }
    out
}

#[cfg(test)]
mod tests;
