use super::*;

#[test]
fn strips_rtl_override() {
    // U+202E RIGHT-TO-LEFT OVERRIDE embedded mid-string (classic bidi spoof).
    let input = "pay\u{202E}dlrow_olleh.exe";
    let sanitized = sanitize_user_text(input);
    assert_eq!(sanitized, "paydlrow_olleh.exe");
    assert!(!sanitized.chars().any(|c| c == '\u{202E}'));
}

#[test]
fn strips_all_bidi_controls() {
    // Exhaustive: every codepoint in the stripped bidi ranges should be removed.
    let codepoints: Vec<char> = (0x202A..=0x202E)
        .chain(0x2066..=0x2069)
        .filter_map(char::from_u32)
        .collect();
    let mut input = String::from("a");
    for c in &codepoints {
        input.push(*c);
    }
    input.push('b');
    assert_eq!(sanitize_user_text(&input), "ab");
}

#[test]
fn strips_zero_width_space() {
    // ZWSP splitting "admin" into two tokens that look identical to "admin".
    let input = "ad\u{200B}min";
    assert_eq!(sanitize_user_text(input), "admin");
}

#[test]
fn strips_lrm_rlm() {
    // U+200E LEFT-TO-RIGHT MARK and U+200F RIGHT-TO-LEFT MARK steer
    // bidi rendering even on otherwise-LTR text. Strip per #2941-M4.
    assert_eq!(sanitize_user_text("ad\u{200E}min"), "admin");
    assert_eq!(sanitize_user_text("ad\u{200F}min"), "admin");
}

#[test]
fn strips_mongolian_vowel_separator() {
    // U+180E MONGOLIAN VOWEL SEPARATOR became default-ignorable in
    // Unicode 6.3 and behaves as a zero-width separator in many
    // renderers — same lookup-splitting hazard as ZWSP.
    let input = "ad\u{180E}min";
    assert_eq!(sanitize_user_text(input), "admin");
}

/// ALM (U+061C) is the Arabic-script bidi mark
/// counterpart to LRM/RLM. Strip alongside.
#[test]
fn strips_arabic_letter_mark() {
    assert_eq!(sanitize_user_text("ad\u{061C}min"), "admin");
}

/// word-joiner + function-call invisible
/// operators all render zero-width.
#[test]
fn strips_word_joiner_and_invisible_operators() {
    // Word joiner.
    assert_eq!(sanitize_user_text("ad\u{2060}min"), "admin");
    // Function application / invisible times / invisible separator
    // / invisible plus.
    assert_eq!(sanitize_user_text("ad\u{2061}min"), "admin");
    assert_eq!(sanitize_user_text("ad\u{2062}min"), "admin");
    assert_eq!(sanitize_user_text("ad\u{2063}min"), "admin");
    assert_eq!(sanitize_user_text("ad\u{2064}min"), "admin");
}

#[test]
fn strips_zwnj_zwj_bom() {
    let input = "a\u{200C}b\u{200D}c\u{FEFF}d";
    assert_eq!(sanitize_user_text(input), "abcd");
}

#[test]
fn strips_line_paragraph_separators() {
    let input = "hello\u{2028}world\u{2029}!";
    assert_eq!(sanitize_user_text(input), "helloworld!");
}

#[test]
fn preserves_cjk_text() {
    let input = "工作清单 — 今天";
    assert_eq!(sanitize_user_text(input), input);
}

#[test]
fn preserves_emoji() {
    let input = "🎯 Daily focus 🚀";
    assert_eq!(sanitize_user_text(input), input);
}

#[test]
fn preserves_rtl_letters() {
    // Actual Arabic letters are allowed; only the OVERRIDE controls are stripped.
    let input = "مرحبا";
    assert_eq!(sanitize_user_text(input), input);
}

#[test]
fn preserves_regular_whitespace_and_newlines() {
    // Normal space, tab, and newline are legitimate and must not be stripped.
    let input = "line one\nline\ttwo";
    assert_eq!(sanitize_user_text(input), input);
}

#[test]
fn normalizes_to_nfc() {
    // Decomposed e-acute (U+0065 U+0301) collapses to composed (U+00E9).
    let decomposed = "cafe\u{0301}";
    let composed = "caf\u{00E9}";
    assert_eq!(sanitize_user_text(decomposed), composed);
}

#[test]
fn empty_string_ok() {
    assert_eq!(sanitize_user_text(""), "");
}

#[test]
fn only_disallowed_chars_yields_empty() {
    let input = "\u{202E}\u{200B}\u{FEFF}\u{2028}";
    assert_eq!(sanitize_user_text(input), "");
}

#[test]
fn idempotent() {
    let input = "Hello\u{202E} 世界\u{200B}! café";
    let once = sanitize_user_text(input);
    let twice = sanitize_user_text(&once);
    assert_eq!(once, twice);
}

#[test]
fn preserves_accented_latin() {
    assert_eq!(
        sanitize_user_text("café naïve jalapeño"),
        "café naïve jalapeño"
    );
}

// C0/C1 control codepoint stripping.

#[test]
fn strips_null_byte() {
    // Null in a title would truncate at some display layers and
    // break FTS5 indexing. Strip it at the write boundary.
    let input = "foo\x00bar";
    assert_eq!(sanitize_user_text(input), "foobar");
}

#[test]
fn strips_ansi_escape_introducer() {
    // U+001B (ESC) enables ANSI terminal escape sequences. An
    // MCP client running in a terminal would render "\x1B[2J"
    // embedded in a title as a screen clear.
    let input = "clean\x1B[2Jme";
    let sanitized = sanitize_user_text(input);
    assert!(
        !sanitized.chars().any(|c| c == '\x1B'),
        "ESC should be stripped, got: {sanitized:?}"
    );
}

#[test]
fn strips_all_c0_controls_except_tab_lf_cr() {
    for cp in 0x00u32..=0x1F {
        let c = char::from_u32(cp).unwrap();
        let input = format!("a{c}b");
        let out = sanitize_user_text(&input);
        if c == '\t' || c == '\n' || c == '\r' {
            assert_eq!(out, input, "whitespace U+{cp:04X} must be preserved");
        } else {
            assert_eq!(out, "ab", "control U+{cp:04X} must be stripped");
        }
    }
}

#[test]
fn strips_all_c1_controls() {
    for cp in 0x80u32..=0x9F {
        let c = char::from_u32(cp).unwrap();
        let input = format!("a{c}b");
        // The sanitizer is expected to drop every C1; don't
        // assert exact equality because NFC may re-combine the
        // surrounding chars differently. Just check the control
        // itself is gone.
        let out = sanitize_user_text(&input);
        assert!(
            !out.chars().any(|x| x == c),
            "C1 U+{cp:04X} leaked through: {out:?}"
        );
    }
}

#[test]
fn preserves_tab_newline_cr() {
    let input = "line1\nline2\tcol\rcol2";
    assert_eq!(sanitize_user_text(input), input);
}

/// nested string leaves inside a JSON object value
/// must scrub through the same hygiene pass as flat-text fields.
#[test]
fn json_object_string_leaves_are_scrubbed() {
    let mut value = serde_json::json!({
        "display_name": "Bob\u{202E}resu_",
        "tagline": "ad\u{200B}min",
    });
    sanitize_user_text_in_json_in_place(&mut value);
    assert_eq!(value["display_name"], serde_json::json!("Bobresu_"));
    assert_eq!(value["tagline"], serde_json::json!("admin"));
}

/// arrays must traverse element-by-element so an
/// invisible-control payload can't hide one level deep.
#[test]
fn json_array_string_leaves_are_scrubbed() {
    let mut value = serde_json::json!(["clean", "ad\u{200B}min", ["nested", "pay\u{202E}exe"],]);
    sanitize_user_text_in_json_in_place(&mut value);
    assert_eq!(
        value,
        serde_json::json!(["clean", "admin", ["nested", "payexe"]])
    );
}

/// object KEYS are not scrubbed because keys are
/// schema-defined identifiers; rewriting them would silently
/// change the stored object's shape and break round-trip equality
/// at every reader. Pin this contract.
#[test]
fn json_object_keys_are_not_scrubbed() {
    let key = "display\u{200B}name";
    let mut map = serde_json::Map::new();
    map.insert(key.to_string(), serde_json::json!("clean"));
    let mut value = serde_json::Value::Object(map);
    sanitize_user_text_in_json_in_place(&mut value);
    // The key still carries the ZWSP — only the value would scrub.
    let object = value.as_object().unwrap();
    assert!(
        object.contains_key(key),
        "object keys must be left intact: {object:?}"
    );
}

/// numbers, booleans, and null carry no string data
/// and must pass through verbatim.
#[test]
fn json_non_string_leaves_pass_through() {
    let mut value = serde_json::json!({
        "n": 42,
        "b": true,
        "null": null,
        "arr": [1, 2, false],
    });
    let snapshot = value.clone();
    sanitize_user_text_in_json_in_place(&mut value);
    assert_eq!(value, snapshot);
}

/// deep nesting walks every level. The bidi override
/// 4 levels deep must still be scrubbed — a partial walk would
/// leak the attack vector at the leaf.
#[test]
fn json_deep_nesting_scrubs_every_level() {
    let mut value = serde_json::json!({
        "level1": {
            "level2": [
                { "level3": "ad\u{200B}min" },
            ],
        },
    });
    sanitize_user_text_in_json_in_place(&mut value);
    assert_eq!(value["level1"]["level2"][0]["level3"], "admin");
}
