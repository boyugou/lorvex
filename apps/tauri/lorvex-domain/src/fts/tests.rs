//! Tests for `fts`. Extracted from the parent file
//! to keep the production module focused.

use super::*;

#[test]
fn single_token_gets_prefix_wildcard() {
    assert_eq!(sanitize_fts_query("gro"), "\"gro\"*");
}

#[test]
fn last_token_gets_prefix_wildcard() {
    assert_eq!(sanitize_fts_query("hello world"), "\"hello\" \"world\"*");
}

#[test]
fn special_chars_split_into_subtokens() {
    // non-alphanumeric in the middle of a token used
    // to collapse into a single quoted phrase with unicode61
    // re-splitting inside, which forced ordered adjacency. Now each
    // subtoken is quoted independently (AND, unordered) — except
    // for email-like (`@`/`.`) tokens, which issue #2719 preserves
    // as phrases.
    assert_eq!(sanitize_fts_query("foo*bar"), "\"foo\" \"bar\"*");
    // Single-word quoted input becomes a `Word` unit — the prefix
    // wildcard lands on the sole word.
    assert_eq!(sanitize_fts_query("\"quoted\""), "\"quoted\"*");
}

#[test]
fn empty_input_returns_empty() {
    assert_eq!(sanitize_fts_query(""), "");
    assert_eq!(sanitize_fts_query("   "), "");
}

#[test]
fn all_special_chars_yields_empty() {
    assert_eq!(sanitize_fts_query("\"*()"), "");
}

#[test]
fn control_characters_are_stripped() {
    // control chars are non-alphanumeric, so they
    // now split subtokens (same behavior as any other non-alnum).
    // Both hello\0world → ["hello","world"] and test\x01\x02\x03 →
    // ["test"] are strictly cleaner results.
    assert_eq!(sanitize_fts_query("hello\0world"), "\"hello\" \"world\"*");
    assert_eq!(sanitize_fts_query("test\x01\x02\x03"), "\"test\"*");
    assert_eq!(sanitize_fts_query("a\tb"), "\"a\" \"b\"*");
}

#[test]
fn very_long_input_is_truncated_to_64_tokens() {
    let long_input = (0..200)
        .map(|i| format!("word{i}"))
        .collect::<Vec<_>>()
        .join(" ");

    let result = sanitize_fts_query(&long_input);
    let token_count = result.matches('"').count() / 2;

    assert_eq!(token_count, 64);
}

#[test]
fn cjk_tokens_pass_through() {
    // CJK characters are alphanumeric per Rust's Unicode-aware
    // char::is_alphanumeric, so they don't split.
    assert_eq!(sanitize_fts_query("买牛奶"), "\"买牛奶\"*");
}

#[test]
fn emoji_only_subtokens_drop() {
    // emoji are non-alphanumeric so the new subtoken
    // split filters them out of mixed queries. unicode61 would
    // have produced zero tokens for the emoji anyway, so dropping
    // it is a strict improvement.
    assert_eq!(sanitize_fts_query("🎯 goals"), "\"goals\"*");
}

#[test]
fn punctuation_splits_into_subtokens() {
    // previously these collapsed into ordered-
    // adjacency phrase queries; now each alphanumeric run is its
    // own token under AND semantics — except for `@`/`.`-separated
    // identifiers, which issue #2719 preserves as phrases.
    assert_eq!(sanitize_fts_query("2024-Q1"), "\"2024\" \"Q1\"*");
    assert_eq!(sanitize_fts_query("foo-bar"), "\"foo\" \"bar\"*");
    assert_eq!(sanitize_fts_query("2026-04-17"), "\"2026\" \"04\" \"17\"*");
}

// -- issue #2719: email / dotted-identifier phrase preservation --

#[test]
fn email_like_token_becomes_phrase() {
    // `alice@example.com` previously tokenized to
    // `"alice" "example" "com"*` — an AND combination that falsely
    // matched tasks containing all three words in any order. Now
    // the whole identifier is emitted as an ordered phrase whose
    // final word carries the prefix wildcard.
    assert_eq!(
        sanitize_fts_query("alice@example.com"),
        "\"alice example com\"*",
    );
}

#[test]
fn dotted_version_tokens_become_phrase() {
    // Dotted identifiers are the same class: ordered adjacency
    // is what the user means when they type them.
    assert_eq!(sanitize_fts_query("v1.2.3"), "\"v1 2 3\"*");
}

#[test]
fn email_token_alongside_other_words_keeps_phrase_semantics() {
    // The email-like token stays a phrase; the other words remain
    // independent AND-combined word units.
    assert_eq!(
        sanitize_fts_query("email alice@example.com"),
        "\"email\" \"alice example com\"*",
    );
}

#[test]
fn hyphenated_non_dotted_token_still_splits() {
    // No `@`/`.` in `project-alpha` → still split into words, not
    // a phrase. This preserves the fix for things
    // like `2024-Q1` where AND semantics matter.
    assert_eq!(
        sanitize_fts_query("project-alpha"),
        "\"project\" \"alpha\"*",
    );
}

// -- issue #2719: quoted phrase preservation --

#[test]
fn quoted_phrase_is_preserved_as_fts5_phrase() {
    // Input `"exact phrase"` must survive as a single FTS5 phrase
    // with the prefix wildcard attached to the final word.
    assert_eq!(sanitize_fts_query("\"exact phrase\""), "\"exact phrase\"*",);
}

#[test]
fn quoted_phrase_with_following_bare_token() {
    // Mixed input: phrase first (non-last → no wildcard), then a
    // bare trailing word that gets the wildcard.
    assert_eq!(
        sanitize_fts_query("\"exact phrase\" more"),
        "\"exact phrase\" \"more\"*",
    );
}

#[test]
fn quoted_phrase_last_carries_wildcard() {
    assert_eq!(
        sanitize_fts_query("bare \"exact phrase\""),
        "\"bare\" \"exact phrase\"*",
    );
}

#[test]
fn unterminated_quote_is_tolerated() {
    // Typed-ahead: `foo "bar baz` — treat the rest as the phrase
    // body and still produce a usable query.
    assert_eq!(sanitize_fts_query("foo \"bar baz"), "\"foo\" \"bar baz\"*",);
}

#[test]
fn empty_quotes_are_dropped() {
    assert_eq!(sanitize_fts_query("foo \"\" bar"), "\"foo\" \"bar\"*");
}

#[test]
fn fts_keywords_remain_literal_when_quoted() {
    assert_eq!(sanitize_fts_query("AND"), "\"AND\"*");
    assert_eq!(sanitize_fts_query("NOT hello"), "\"NOT\" \"hello\"*");
    assert_eq!(sanitize_fts_query("a OR b"), "\"a\" \"OR\" \"b\"*");
}

// -- contains_cjk --

#[test]
fn contains_cjk_detects_chinese() {
    assert!(contains_cjk("中文"));
    assert!(contains_cjk("写一个中文任务"));
    assert!(contains_cjk("buy 牛奶"));
}

#[test]
fn contains_cjk_detects_japanese() {
    assert!(contains_cjk("こんにちは")); // Hiragana
    assert!(contains_cjk("カタカナ")); // Katakana
    assert!(contains_cjk("漢字")); // Kanji (CJK Unified)
}

#[test]
fn contains_cjk_detects_korean() {
    assert!(contains_cjk("한국어")); // Hangul Syllables
}

#[test]
fn contains_cjk_rejects_latin() {
    assert!(!contains_cjk("hello world"));
    assert!(!contains_cjk("groceries"));
    assert!(!contains_cjk(""));
    assert!(!contains_cjk("🎯 goals"));
}

#[test]
fn contains_cjk_mixed_scripts() {
    assert!(contains_cjk("buy 牛奶 tomorrow"));
    assert!(contains_cjk("task: 完成报告"));
}

// -- length caps

#[test]
fn cap_fts_query_length_truncates_long_input() {
    let long = "a".repeat(10_000);
    let capped = cap_fts_query_length(&long);
    assert_eq!(capped.len(), MAX_FTS_QUERY_CHARS);
}

#[test]
fn cap_fts_query_length_respects_unicode_boundary() {
    let input = "a".repeat(MAX_FTS_QUERY_CHARS - 1) + "中";
    let capped = cap_fts_query_length(&input);
    assert!(capped.ends_with("中"));
    assert_eq!(capped.chars().count(), MAX_FTS_QUERY_CHARS);
}

#[test]
fn sanitize_truncates_per_token() {
    let giant = "a".repeat(10_000);
    let sanitized = sanitize_fts_query(&giant);
    // "<64 a's>"* — 64 chars inside the quotes.
    let inner: String = sanitized
        .trim_start_matches('"')
        .trim_end_matches('*')
        .trim_end_matches('"')
        .to_string();
    assert_eq!(inner.len(), MAX_FTS_TOKEN_CHARS);
}

#[test]
fn sanitize_10k_char_blob_does_not_explode() {
    let huge = "x".repeat(20_000);
    let result = sanitize_fts_query(&huge);
    // A single oversized token collapses to a single 64-char prefix wildcard.
    assert!(result.starts_with('"'));
    assert!(result.ends_with("\"*"));
    assert!(result.len() < 80);
}

// -- should_use_like_fallback

#[test]
fn should_use_like_fallback_true_for_cjk() {
    assert!(should_use_like_fallback("中文"));
    assert!(should_use_like_fallback("买 牛奶"));
}

#[test]
fn should_use_like_fallback_true_for_emoji_only() {
    assert!(should_use_like_fallback("🚀"));
    assert!(should_use_like_fallback("🎯 🚀"));
}

#[test]
fn should_use_like_fallback_true_for_punctuation_only() {
    assert!(should_use_like_fallback("---"));
    assert!(should_use_like_fallback("..."));
    assert!(should_use_like_fallback("!?&*"));
}

#[test]
fn should_use_like_fallback_false_for_alnum_query() {
    assert!(!should_use_like_fallback("hello"));
    assert!(!should_use_like_fallback("buy groceries"));
    assert!(!should_use_like_fallback("task-123"));
}

#[test]
fn should_use_like_fallback_false_for_mixed_emoji_and_alnum() {
    // When there's even one alphanumeric char, FTS can handle it.
    assert!(!should_use_like_fallback("🚀 ship"));
    assert!(!should_use_like_fallback("goals 🎯"));
}

// -- short_trailing_token_for_like_retry (issue #2719) --

#[test]
fn short_trailing_token_flags_2_and_3_char_trailers() {
    assert_eq!(
        short_trailing_token_for_like_retry("oject"),
        None,
        "5-char trailer is long enough to rely on prefix matching"
    );
    assert_eq!(short_trailing_token_for_like_retry("ab"), Some("ab"));
    assert_eq!(short_trailing_token_for_like_retry("foo ab"), Some("ab"));
    assert_eq!(short_trailing_token_for_like_retry("foo abc"), Some("abc"));
}

#[test]
fn short_trailing_token_rejects_single_char() {
    // A single char produces far too many false positives under
    // substring matching — leave it to plain FTS prefix.
    assert_eq!(short_trailing_token_for_like_retry("a"), None);
    assert_eq!(short_trailing_token_for_like_retry("foo a"), None);
}

#[test]
fn short_trailing_token_rejects_long_trailer() {
    assert_eq!(short_trailing_token_for_like_retry("foobar"), None);
    assert_eq!(short_trailing_token_for_like_retry("foo barbaz"), None);
}

#[test]
fn short_trailing_token_rejects_empty_or_whitespace() {
    assert_eq!(short_trailing_token_for_like_retry(""), None);
    assert_eq!(short_trailing_token_for_like_retry("   "), None);
}

#[test]
fn short_trailing_token_rejects_quoted_trailer() {
    // A closing `"` means the user was explicit about phrase
    // matching; don't second-guess them with a LIKE retry.
    assert_eq!(short_trailing_token_for_like_retry("\"abc\""), None);
    assert_eq!(short_trailing_token_for_like_retry("foo \"bar\""), None);
}

#[test]
fn short_trailing_token_rejects_email_like_trailer() {
    // If the trailing run is preceded by `@` or `.` we're inside
    // an email-/dotted-identifier pattern (which will be emitted
    // as a phrase). Retrying on the last segment alone would
    // either over-match or mislead.
    assert_eq!(
        short_trailing_token_for_like_retry("alice@example.com"),
        None
    );
    assert_eq!(short_trailing_token_for_like_retry("v1.2.3"), None);
    assert_eq!(short_trailing_token_for_like_retry("foo.ab"), None);
}

#[test]
fn short_trailing_token_accepts_trailer_after_hyphen() {
    // Hyphens are not the email-heuristic's concern. `foo-ab` is
    // split into [foo, ab] AND-combined, and `ab` is the short
    // trailing word we'd like to retry as LIKE %ab%.
    assert_eq!(short_trailing_token_for_like_retry("foo-ab"), Some("ab"));
}
