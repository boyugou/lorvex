use super::*;

/// A panic inside `body()` must still restore the previous
/// `DB_PATH` before the panic resumes.
#[test]
fn with_db_path_env_for_test_restores_on_body_panic() {
    #[derive(Debug, PartialEq, Eq)]
    struct DbPathPanicToken(u128);

    const INNER_DB_PATH: &str = "/tmp/lorvex-h4-inner.sqlite";
    const SENTINEL_DB_PATH: &str = "/tmp/lorvex-h4-sentinel.sqlite";
    const PANIC_TOKEN: DbPathPanicToken = DbPathPanicToken(0x3079_5eed_5eed_5eed);

    let original_db_path = std::cell::RefCell::new(None::<Option<String>>);
    let restore_observation = std::cell::RefCell::new(None::<(Option<String>, Option<String>)>);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        with_db_path_env_for_test_impl(
            Some(INNER_DB_PATH),
            || {
                let original = std::env::var("DB_PATH").ok();
                *original_db_path.borrow_mut() = Some(original);
                // Safety: this callback runs while the helper
                // holds the shared DB_PATH mutex.
                unsafe {
                    std::env::set_var("DB_PATH", SENTINEL_DB_PATH);
                }
            },
            || {
                assert_eq!(
                    std::env::var("DB_PATH").ok().as_deref(),
                    Some(INNER_DB_PATH),
                );
                std::panic::panic_any(PANIC_TOKEN);
            },
            |previous| {
                *restore_observation.borrow_mut() =
                    Some((previous.map(str::to_owned), std::env::var("DB_PATH").ok()));
                let original = original_db_path
                    .borrow()
                    .clone()
                    .expect("before-snapshot callback must record original DB_PATH");
                // Safety: this callback runs while the helper
                // holds the shared DB_PATH mutex.
                unsafe {
                    match original {
                        Some(value) => std::env::set_var("DB_PATH", value),
                        None => std::env::remove_var("DB_PATH"),
                    }
                }
            },
        );
    }));
    let payload = result.expect_err("body() panic must propagate as Err");
    assert_eq!(
        payload.downcast_ref::<DbPathPanicToken>(),
        Some(&PANIC_TOKEN),
        "body() panic payload must resume without being replaced",
    );
    let (previous, observed) = restore_observation
        .into_inner()
        .expect("after-restore callback must run before unwinding");
    assert_eq!(
        previous.as_deref(),
        Some(SENTINEL_DB_PATH),
        "test setup must force a known previous DB_PATH value under the helper lock",
    );
    assert_eq!(
        observed, previous,
        "DB_PATH must be restored before a panicking body() unwinds out of the helper",
    );
}
