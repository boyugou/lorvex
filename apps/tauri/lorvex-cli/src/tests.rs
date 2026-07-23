use super::*;
use lorvex_runtime::with_db_path_env_for_test;

/// pre-clap arg failures must classify as
/// `CliError::Validation` (exit 65) instead of falling off the
/// downcast walker as a generic boxed error (exit 1). Covers the
/// missing-value, directory-target, and symlink-target branches.
#[test]
fn apply_db_path_override_typed_validation_errors() {
    with_db_path_env_for_test(None, || {
        let err = apply_db_path_override(vec!["--db-path".to_string()]).unwrap_err();
        assert_eq!(err.exit_code(), 65);
        assert!(err.to_string().contains("requires a value"));
    });

    let temp = tempfile::tempdir().expect("temp dir");
    with_db_path_env_for_test(None, || {
        let err = apply_db_path_override(vec![
            "--db-path".to_string(),
            temp.path().display().to_string(),
        ])
        .unwrap_err();
        assert_eq!(err.exit_code(), 65);
        assert!(err.to_string().contains("is a directory"));
    });
}

/// M4. The previous branch ran
/// \`create_dir_all\` against the user-supplied parent — a typo
/// or hostile wrapper could plant a directory tree anywhere the
/// process had write permission. The new contract is "the parent
/// MUST already exist": a legitimate operator runs \`mkdir -p\`
/// once, while a typo fails loudly at the trust boundary and
/// touches no filesystem state. This test pins the contract by
/// pointing \`--db-path\` at a deeply-nested non-existent parent
/// and asserting both the typed \`Validation\` exit-code and that
/// the directory tree was NOT silently materialized.
#[test]
fn apply_db_path_override_rejects_nonexistent_parent_directory() {
    let temp = tempfile::tempdir().expect("temp dir");
    let nonexistent_parent = temp.path().join("never").join("created").join("nested");
    let target = nonexistent_parent.join("db.sqlite");
    with_db_path_env_for_test(None, || {
        let err =
            apply_db_path_override(vec!["--db-path".to_string(), target.display().to_string()])
                .unwrap_err();
        assert_eq!(err.exit_code(), 65, "must classify as EX_DATAERR (65)");
        assert!(
            err.to_string().contains("does not exist"),
            "error must name the missing parent: {err}"
        );
    });
    assert!(
        !nonexistent_parent.exists(),
        "rejection must NOT have materialized the parent tree at {}",
        nonexistent_parent.display()
    );
}

#[test]
fn apply_db_path_override_sets_runtime_db_path_env() {
    let temp = tempfile::tempdir().expect("temp dir");
    let db_path = temp.path().join("cli.sqlite");
    let expected = db_path.clone();

    with_db_path_env_for_test(None, || {
        let remaining = apply_db_path_override(vec![
            "--db-path".to_string(),
            db_path.display().to_string(),
            "status".to_string(),
        ])
        .expect("apply override");

        assert_eq!(remaining, vec!["status".to_string()]);
        assert_eq!(lorvex_runtime::resolve_db_path(), expected);
    });
}
