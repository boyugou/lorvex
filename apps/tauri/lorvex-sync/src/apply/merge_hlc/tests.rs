use super::*;

#[test]
fn increments_counter_when_room_remains_in_same_physical_ms() {
    let max_hlc = Hlc::parse("1711234567890_0001_dec0000100000001").unwrap();
    let minted = mint_merge_hlc_after(&max_hlc, "dec0000200000002", "test merge").unwrap();

    assert_eq!(minted.to_string(), "1711234567890_0002_dec0000200000002");
    assert!(minted > max_hlc);
}

#[test]
fn rolls_to_next_physical_ms_when_counter_is_exhausted() {
    let max_hlc = Hlc::new(1_711_234_567_890, MAX_COUNTER, "dec0000100000001").unwrap();
    let minted = mint_merge_hlc_after(&max_hlc, "dec0000200000002", "test merge").unwrap();

    assert_eq!(minted.to_string(), "1711234567891_0000_dec0000200000002");
    assert!(minted > max_hlc);
}

#[test]
fn rejects_ceiling_when_no_canonical_successor_exists() {
    let max_hlc = Hlc::new(MAX_HLC_PHYSICAL_MS, MAX_COUNTER, "dec0000100000001").unwrap();
    let err = mint_merge_hlc_after(&max_hlc, "dec0000200000002", "test merge")
        .expect_err("ceiling HLC has no canonical successor");

    match err {
        ApplyError::InvalidVersion(message) => {
            assert!(
                message.contains("test merge")
                    && message.contains("no canonical HLC successor")
                    && message.contains(&max_hlc.to_string()),
                "unexpected error message: {message}"
            );
        }
        other => panic!("expected InvalidVersion, got {other:?}"),
    }
}
