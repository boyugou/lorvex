use super::*;

/// lock the materialized `select_clause` against
/// drift versus the source `all` slice. If a future edit adds a
/// column to `all` without updating `select_clause` (or vice
/// versa), this test fires before any caller can observe the
/// inconsistency.
///
/// Entries that are SQL expressions (containing `(`) carry the
/// placeholder `__OWNER_PREFIX__.id` to be resolved by
/// `select_clause_qualified`; the unqualified `select_clause` is
/// expected to pre-substitute the placeholder to `<table>.id`.
fn assert_clause_matches(cols: &Columns) {
    let computed = build_unqualified_clause(cols.all, cols.table);
    assert_eq!(
        computed.as_str(),
        cols.select_clause,
        "select_clause for {} drifted from all",
        cols.table
    );
    let computed_wov = build_unqualified_clause(cols.without_version, cols.table);
    assert_eq!(
        computed_wov.as_str(),
        cols.select_clause_without_version,
        "select_clause_without_version for {} drifted from without_version",
        cols.table
    );
}

fn build_unqualified_clause(entries: &[&str], table: &str) -> String {
    entries
        .iter()
        .map(|c| {
            if c.contains('(') {
                c.replace("__OWNER_PREFIX__.id", &format!("{table}.id"))
            } else {
                (*c).to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(", ")
}

#[test]
fn tasks_clause_matches_slice() {
    assert_clause_matches(&TASKS);
}

#[test]
fn lists_clause_matches_slice() {
    assert_clause_matches(&LISTS);
}

#[test]
fn habits_clause_matches_slice() {
    assert_clause_matches(&HABITS);
}

#[test]
fn calendar_events_clause_matches_slice() {
    assert_clause_matches(&CALENDAR_EVENTS);
}

#[test]
fn ai_changelog_clause_matches_slice() {
    assert_clause_matches(&AI_CHANGELOG);
}

#[test]
fn without_version_strips_only_version() {
    for cols in [&TASKS, &LISTS, &HABITS, &CALENDAR_EVENTS] {
        for col in cols.without_version {
            assert_ne!(
                *col, "version",
                "without_version for {} contains the version column",
                cols.table
            );
            assert!(
                cols.all.contains(col),
                "without_version for {} has unknown column {col}",
                cols.table
            );
        }
        // Every column in `all` except `version` must appear in
        // `without_version` (the trim is exactly the version
        // column, never more).
        for col in cols.all {
            if *col == "version" {
                continue;
            }
            assert!(
                cols.without_version.contains(col),
                "without_version for {} is missing {col}",
                cols.table
            );
        }
    }
}

#[test]
fn qualified_clause_prefixes_every_column() {
    let qualified = TASKS.select_clause_qualified("t");
    assert!(qualified.starts_with("t.id"), "got: {qualified}");
    assert!(qualified.contains(", t.archived_at"));
    // Bare-name columns are prefixed with `t.`; SQL-expression
    // entries (containing `(`) carry `__OWNER_PREFIX__.id` which
    // the qualifier substitutes to `t.id`, so they don't appear in
    // the `t.<bare>` form. Check both shapes.
    for col in TASKS.all {
        if col.contains('(') {
            let expected = col.replace("__OWNER_PREFIX__.id", "t.id");
            assert!(
                qualified.contains(&expected),
                "qualified clause missing expression-form column for {col}: {qualified}"
            );
        } else {
            let prefixed = format!("t.{col}");
            assert!(
                qualified.contains(&prefixed),
                "qualified clause missing {prefixed}: {qualified}"
            );
        }
    }
}
