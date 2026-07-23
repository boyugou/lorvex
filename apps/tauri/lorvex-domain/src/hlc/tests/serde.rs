use crate::hlc::*;

#[test]
fn serde_roundtrip() {
    let hlc = Hlc::new(1_711_234_567_890, 7, "cafe1234cafe1234").unwrap();
    let json = serde_json::to_string(&hlc).unwrap();
    assert_eq!(json, "\"1711234567890_0007_cafe1234cafe1234\"");
    let deserialized: Hlc = serde_json::from_str(&json).unwrap();
    assert_eq!(hlc, deserialized);
}

#[test]
fn serde_deserialize_invalid() {
    let result = serde_json::from_str::<Hlc>("\"invalid\"");
    assert!(result.is_err());
}
