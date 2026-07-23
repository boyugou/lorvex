use super::*;

#[test]
fn strips_ansi_escape() {
    let input = "A\u{001B}[31mRED\u{001B}[0m";
    assert_eq!(strip_dangerous_codepoints(input), "A[31mRED[0m");
}

#[test]
fn strips_null_byte() {
    assert_eq!(
        strip_dangerous_codepoints("before\u{0000}after"),
        "beforeafter"
    );
}

#[test]
fn strips_bidi_override() {
    // Right-to-left override (U+202E) — classic filename-spoofing char.
    assert_eq!(
        strip_dangerous_codepoints("invoice\u{202E}gpj.exe"),
        "invoicegpj.exe"
    );
}

#[test]
fn strips_zero_width_and_bom() {
    assert_eq!(
        strip_dangerous_codepoints("foo\u{200B}bar\u{FEFF}baz"),
        "foobarbaz"
    );
}

#[test]
fn strips_c1_control_range() {
    assert_eq!(
        strip_dangerous_codepoints("ok\u{0085}still\u{009F}ok"),
        "okstillok"
    );
}

#[test]
fn strips_bidi_isolates() {
    assert_eq!(strip_dangerous_codepoints("a\u{2066}b\u{2069}c"), "abc");
}

#[test]
fn preserves_newline_and_tab() {
    assert_eq!(
        strip_dangerous_codepoints("line1\nline2\tindented"),
        "line1\nline2\tindented"
    );
}

#[test]
fn preserves_emoji_and_cjk() {
    let input = "🗓️ 会议: 10:00";
    assert_eq!(strip_dangerous_codepoints(input), input);
}

#[test]
fn drops_bare_cr() {
    assert_eq!(strip_dangerous_codepoints("A\rB"), "AB");
}

/// LRM and RLM strip alongside
/// the override range so peer text can't smuggle bidi marks past
/// the scrubber.
#[test]
fn strips_lrm_rlm() {
    assert_eq!(strip_dangerous_codepoints("ad\u{200E}min"), "admin");
    assert_eq!(strip_dangerous_codepoints("ad\u{200F}min"), "admin");
}

/// Mongolian Vowel Separator
/// behaves as zero-width on most renderers; strip alongside ZWSP.
#[test]
fn strips_mongolian_vowel_separator() {
    assert_eq!(strip_dangerous_codepoints("ad\u{180E}min"), "admin");
}

/// Unicode line/paragraph
/// separators are stripped so peer text can't insert bare-LSEP
/// breaks past the canonicalizer.
#[test]
fn strips_line_paragraph_separators() {
    assert_eq!(
        strip_dangerous_codepoints("hello\u{2028}world\u{2029}!"),
        "helloworld!"
    );
}

#[test]
fn empty_input_returns_empty() {
    assert_eq!(strip_dangerous_codepoints(""), "");
}

#[test]
fn input_with_no_dangerous_chars_is_unchanged() {
    let input = "Hello, world! — résumé café";
    assert_eq!(strip_dangerous_codepoints(input), input);
}
