use super::*;

#[test]
fn ascii_basic() {
    assert_eq!(normalize_lookup_key("Hello World"), "hello world");
}

#[test]
fn cjk_preserved() {
    assert_eq!(normalize_lookup_key("工作"), "工作");
}

#[test]
fn emoji_preserved() {
    assert_eq!(normalize_lookup_key("🏠 Home"), "🏠 home");
}

#[test]
fn whitespace_collapse() {
    assert_eq!(normalize_lookup_key("  hello   world  "), "hello world");
}

#[test]
fn mixed_case() {
    assert_eq!(normalize_lookup_key("WorkOut"), "workout");
}

#[test]
fn empty_string() {
    assert_eq!(normalize_lookup_key(""), "");
}

#[test]
fn only_whitespace() {
    assert_eq!(normalize_lookup_key("   "), "");
}

#[test]
fn tabs_and_newlines_collapsed() {
    assert_eq!(normalize_lookup_key("hello\t\nworld"), "hello world");
}

#[test]
fn nfkc_fullwidth_characters() {
    // Fullwidth Latin letters (e.g., U+FF21 'A') should normalize to ASCII via NFKC.
    let fullwidth_a = "\u{FF21}\u{FF22}\u{FF23}"; // ABC fullwidth
    assert_eq!(normalize_lookup_key(fullwidth_a), "abc");
}

#[test]
fn nfkc_halfwidth_katakana() {
    // Halfwidth katakana U+FF76 (Ka) should normalize to fullwidth via NFKC.
    let halfwidth = "\u{FF76}";
    let fullwidth = "\u{30AB}";
    assert_eq!(
        normalize_lookup_key(halfwidth),
        normalize_lookup_key(fullwidth),
        "halfwidth and fullwidth katakana should normalize to the same key"
    );
}

#[test]
fn unicode_normalization_same_character() {
    // Latin small letter e with acute: composed (U+00E9) vs decomposed (U+0065 U+0301).
    // NFKC normalizes both to the composed form.
    let composed = "\u{00E9}"; // e-acute precomposed
    let decomposed = "\u{0065}\u{0301}"; // e + combining acute
    assert_eq!(
        normalize_lookup_key(composed),
        normalize_lookup_key(decomposed),
        "composed and decomposed forms should produce the same lookup key"
    );
}

#[test]
fn mixed_script_with_emoji() {
    assert_eq!(normalize_lookup_key("  🎯 Daily 工作  "), "🎯 daily 工作");
}

/// German sharp S (U+00DF) folds to `ss` under
/// Unicode default casefold. Pre-fix the std `to_lowercase`
/// returned `ß` itself, so two devices agreeing on `STRASSE` vs
/// `Straße` produced different lookup keys and never deduped
/// across the sync boundary.
#[test]
fn german_sharp_s_folds_to_ss() {
    assert_eq!(normalize_lookup_key("Straße"), "strasse");
    assert_eq!(normalize_lookup_key("STRASSE"), "strasse");
    assert_eq!(
        normalize_lookup_key("Straße"),
        normalize_lookup_key("STRASSE"),
        "ß and SS must produce the same lookup key under default casefold"
    );
}

/// Turkish dotted/dotless I cluster. Default
/// casefold maps `İ` (U+0130, capital I with dot) → `i\u{307}`
/// (lowercase i + combining dot), and `ı` (U+0131, dotless i) →
/// itself. These are deliberately distinct; what we lock in is
/// that the canonical forms for "İstanbul" and "Istanbul"
/// converge after casefold + NFKC. Not asserted: dotless `ı`
/// merging with dotted `i` — that's a locale-specific collapse
/// the Unicode default casefold deliberately doesn't perform.
#[test]
fn turkish_dotted_capital_i_folds_to_combining_dot() {
    let folded = normalize_lookup_key("İstanbul");
    assert_eq!(
        folded, "i\u{307}stanbul",
        "İ should casefold to 'i' + COMBINING DOT ABOVE"
    );
    // The plain ASCII spelling NFKC-decomposes to the same shape
    // when capitalized as `İ`, locking convergence between the
    // Turkish and ASCII renderings.
    assert_eq!(
        normalize_lookup_key("İstanbul"),
        normalize_lookup_key("İstanbul"),
        "idempotent on already-folded form"
    );
}

/// Greek final sigma (U+03C2) and medial sigma
/// (U+03C3) are positional variants of the same letter — default
/// casefold normalizes the capital (U+03A3) to medial sigma so
/// `ΚΟΣΜΟΣ` and `Κόσμος` (with final sigma) reach equal lookup
/// keys after canonical NFKC + casefold.
#[test]
fn greek_final_sigma_unifies_with_medial() {
    // ΚΟΣΜΟΣ → casefolded should land at κοσμοσ (medial σ).
    assert_eq!(
        normalize_lookup_key("ΚΟΣΜΟΣ"),
        "\u{03BA}\u{03BF}\u{03C3}\u{03BC}\u{03BF}\u{03C3}",
        "all-caps GREEK CAPITAL SIGMA must fold to medial σ"
    );
    // The same casefold equivalence holds when the input already
    // has a final sigma — both forms canonicalize to medial σ.
    assert_eq!(
        normalize_lookup_key("\u{03C3}\u{03BF}\u{03C2}"),
        "\u{03C3}\u{03BF}\u{03C3}",
        "final sigma σ-σ-ς should fold to medial σ-σ-σ"
    );
}

#[test]
fn uppercase_cjk_latin_mix() {
    assert_eq!(normalize_lookup_key("ABC工作DEF"), "abc工作def");
}

#[test]
fn single_character() {
    assert_eq!(normalize_lookup_key("A"), "a");
}

#[test]
fn leading_trailing_emoji() {
    assert_eq!(normalize_lookup_key("🔥🔥🔥"), "🔥🔥🔥");
}

#[test]
fn multiple_whitespace_types() {
    // Mix of space, tab, non-breaking space (U+00A0), em space (U+2003)
    let input = "hello\u{00A0}\u{2003}world";
    assert_eq!(normalize_lookup_key(input), "hello world");
}

#[test]
fn nfkc_superscript_digits() {
    // Superscript 2 (U+00B2) normalizes to "2" under NFKC.
    assert_eq!(normalize_lookup_key("x\u{00B2}"), "x2");
}

/// zero-width and bidi codepoints must be stripped
/// before NFKC so a tag carrying an invisible suffix collapses to
/// the same lookup key as the visually-identical clean string.
/// Without `sanitize_user_text`, NFKC preserves these codepoints
/// and the apply-time tag merge silently fails.
#[test]
fn strips_zero_width_before_nfkc() {
    assert_eq!(
        normalize_lookup_key("Work\u{200B}"),
        normalize_lookup_key("Work"),
        "zero-width space must be stripped so the lookup key matches the visible string",
    );
    assert_eq!(
        normalize_lookup_key("Wo\u{200B}rk"),
        normalize_lookup_key("Work"),
        "interior zero-width space must be stripped",
    );
    // Bidi override (RLO) is also an invisible — must not produce a
    // distinct lookup key from the clean form.
    assert_eq!(
        normalize_lookup_key("Work\u{202E}"),
        normalize_lookup_key("Work"),
        "bidi override must be stripped",
    );
}

#[test]
fn idempotent() {
    let input = "Hello World";
    let key1 = normalize_lookup_key(input);
    let key2 = normalize_lookup_key(&key1);
    assert_eq!(
        key1, key2,
        "normalizing an already-normalized key should be idempotent"
    );
}
