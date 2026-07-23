//! Shared SQL fragments for AI changelog actor filtering.
//!
//! `ai_changelog` is the assistant activity surface. Human/user/system/manual
//! rows can exist for legacy imports or diagnostics, but assistant-facing reads,
//! exports, and retention should all agree on which rows are AI-originated.

const NON_ASSISTANT_ACTORS_SQL: &str = "'human', 'system', 'user', 'manual'";

/// Render the assistant-originated actor predicate for bare-table queries.
#[must_use]
pub fn ai_changelog_assistant_actor_filter_sql() -> String {
    ai_changelog_assistant_actor_filter_sql_for_column("initiated_by")
}

/// Render the assistant-originated actor predicate for an aliased
/// `ai_changelog` table, e.g. `c.initiated_by`.
///
/// The alias is code-owned SQL, not user input. The assertion keeps future
/// callers from accidentally passing a full expression here.
#[must_use]
pub fn ai_changelog_assistant_actor_filter_sql_for_alias(alias: &str) -> String {
    assert_safe_sql_alias(alias);
    ai_changelog_assistant_actor_filter_sql_for_column(&format!("{alias}.initiated_by"))
}

fn ai_changelog_assistant_actor_filter_sql_for_column(column: &str) -> String {
    format!("({column} IS NULL OR {column} NOT IN ({NON_ASSISTANT_ACTORS_SQL}))")
}

fn assert_safe_sql_alias(alias: &str) {
    let mut chars = alias.chars();
    let Some(first) = chars.next() else {
        panic!("ai_changelog SQL alias must not be empty");
    };
    assert!(
        first == '_' || first.is_ascii_alphabetic(),
        "ai_changelog SQL alias must start with an ASCII identifier character",
    );
    assert!(
        chars.all(|ch| ch == '_' || ch.is_ascii_alphanumeric()),
        "ai_changelog SQL alias must be an ASCII identifier",
    );
}

#[cfg(test)]
mod tests {
    use super::{
        ai_changelog_assistant_actor_filter_sql, ai_changelog_assistant_actor_filter_sql_for_alias,
    };

    #[test]
    fn renders_bare_table_predicate() {
        assert_eq!(
            ai_changelog_assistant_actor_filter_sql(),
            "(initiated_by IS NULL OR initiated_by NOT IN ('human', 'system', 'user', 'manual'))"
        );
    }

    #[test]
    fn renders_aliased_predicate() {
        assert_eq!(
            ai_changelog_assistant_actor_filter_sql_for_alias("ac"),
            "(ac.initiated_by IS NULL OR ac.initiated_by NOT IN ('human', 'system', 'user', 'manual'))"
        );
    }

    #[test]
    #[should_panic(expected = "ai_changelog SQL alias must be an ASCII identifier")]
    fn rejects_expression_aliases() {
        let _ = ai_changelog_assistant_actor_filter_sql_for_alias("ac WHERE 1=1");
    }
}
