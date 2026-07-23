use super::*;

fn s(args: &[&str]) -> Vec<String> {
    args.iter().map(std::string::ToString::to_string).collect()
}

#[test]
fn extract_format_strips_flag_and_parses_each_variant() {
    let (rest, fmt) = extract_format_override(s(&["today", "--format", "json"])).unwrap();
    assert_eq!(rest, s(&["today"]));
    assert_eq!(fmt, Some(FormatOverride::Json));

    let (rest, fmt) = extract_format_override(s(&["today", "--format", "text"])).unwrap();
    assert_eq!(rest, s(&["today"]));
    assert_eq!(fmt, Some(FormatOverride::Text));

    // No flag → None (caller preserves existing default).
    let (rest, fmt) = extract_format_override(s(&["today", "-l", "5"])).unwrap();
    assert_eq!(rest, s(&["today", "-l", "5"]));
    assert_eq!(fmt, None);
}

#[test]
fn extract_format_preserves_unknown_args() {
    let input = s(&["cancel", "task-1", "--series", "--unknown", "x"]);
    let (rest, fmt) = extract_format_override(input.clone()).unwrap();
    assert_eq!(rest, input);
    assert_eq!(fmt, None);
}

#[test]
fn extract_format_rejects_bad_value() {
    let err = extract_format_override(s(&["today", "--format", "yaml"])).unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("not recognized"), "error was: {msg}");
    assert_eq!(
        err.exit_code(),
        65,
        "bad --format value must classify as EX_DATAERR (65)"
    );
}

#[test]
fn extract_format_rejects_missing_value() {
    let err = extract_format_override(s(&["today", "--format"])).unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("requires a value"), "error was: {msg}");
    assert_eq!(
        err.exit_code(),
        65,
        "missing --format value must classify as EX_DATAERR (65)"
    );
}

#[test]
fn extract_format_rejects_aliases_and_case_variants() {
    for value in ["JSON", "jsonl", "ndjson", "txt", "plain", "Plain"] {
        let err = extract_format_override(s(&["today", "--format", value])).unwrap_err();
        let msg = err.to_string();
        assert!(
            msg.contains("expected one of: text, json"),
            "error was: {msg}"
        );
        assert_eq!(err.exit_code(), 65);
    }
}

#[test]
fn default_output_format_tracks_supported_values() {
    set_default_output_format(FormatOverride::Json);
    assert_eq!(default_output_format(), OutputFormat::Json);

    set_default_output_format(FormatOverride::Text);
    assert_eq!(default_output_format(), OutputFormat::Text);
}
