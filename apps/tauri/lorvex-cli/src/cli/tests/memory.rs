use super::*;
#[test]
fn parse_memory_preferences_and_tags() {
    assert_eq!(
        parse(&["memory", "list"]),
        Command::Memory(MemoryCommand::List {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["memory", "show", "user_preferences"]),
        Command::Memory(MemoryCommand::Show {
            key: "user_preferences".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "memory",
            "write",
            "user_preferences",
            "likes",
            "deep",
            "work"
        ]),
        Command::Memory(MemoryCommand::Write {
            key: "user_preferences".to_string(),
            content: "likes deep work".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["memory", "delete", "user_preferences"]),
        Command::Memory(MemoryCommand::Delete {
            key: "user_preferences".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["memory", "history", "user_preferences", "--limit", "10"]),
        Command::Memory(MemoryCommand::History {
            key: "user_preferences".to_string(),
            limit: 10,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["memory", "restore", "01900000-0000-7000-8007-000000000001"]),
        Command::Memory(MemoryCommand::Restore {
            revision_id: "01900000-0000-7000-8007-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["preference", "list"]),
        Command::Preferences(PreferencesCommand::List {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["preference", "get", "default_list_id"]),
        Command::Preferences(PreferencesCommand::Get {
            key: "default_list_id".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["preference", "set", "weekly_review_day", "1"]),
        Command::Preferences(PreferencesCommand::Set {
            key: "weekly_review_day".to_string(),
            value_json: "1".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["preference", "delete", "weekly_review_day"]),
        Command::Preferences(PreferencesCommand::Delete {
            key: "weekly_review_day".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["tags"]),
        Command::Tags(TagsCommand::List {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["tag", "tasks", "Deep", "Work"]),
        Command::Tags(TagsCommand::Tasks {
            tag_name: "Deep Work".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["tag", "rename", "Deep Work", "Focus"]),
        Command::Tags(TagsCommand::Rename {
            old_name: "Deep Work".to_string(),
            new_name: "Focus".to_string(),
            format: OutputFormat::Text,
        })
    );
}
