use super::*;

#[test]
#[serial_test::serial(hlc)]
fn passes_when_token_is_live() {
    let ct = CancellationToken::new();
    assert!(check_cancelled(&ct).is_ok());
}

#[test]
#[serial_test::serial(hlc)]
fn returns_cancelled_error_when_token_fires() {
    let ct = CancellationToken::new();
    ct.cancel();
    let err = check_cancelled(&ct).expect_err("cancelled token must short-circuit");
    assert!(matches!(err, McpError::CancelledByClient));
}
