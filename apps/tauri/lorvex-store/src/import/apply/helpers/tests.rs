use super::*;

#[test]
fn enforce_max_field_length_passes_within_cap() {
    let value = "a".repeat(32);
    let out = enforce_max_field_length(value.clone(), 32, "field", "ctx").unwrap();
    assert_eq!(out, value);
}

#[test]
fn enforce_max_field_length_rejects_when_over_cap() {
    // regression-test the import-boundary length
    // cap helper. A 33-byte value against a 32-byte cap must
    // refuse with a precise diagnostic that names the field, the
    // context, and both byte counts so the source archive is
    // identifiable.
    let value = "a".repeat(33);
    let err = enforce_max_field_length(value, 32, "field", "ctx").unwrap_err();
    let message = format!("{err}");
    assert!(
        message.contains("ctx.field"),
        "missing context.field in {message}"
    );
    assert!(
        message.contains("33 bytes"),
        "missing actual length in {message}"
    );
    assert!(message.contains("32 bytes"), "missing cap in {message}");
}
