use super::super::args::{
    ListCmd, ListCreateArgs, ListDeleteArgs, ListHealthArgs, ListShowArgs, ListUpdateArgs,
};
use super::super::command::{Command, ListsCommand, OutputFormat};

/// Collapse a `(value: Option<T>, clear: bool)` flag pair into the
/// canonical `Patch<T>` tri-state used by store patches. Clap's
/// `conflicts_with` ensures the `Some + true` corner is unreachable;
/// debug-assert it explicitly so any future flag wiring change blows
/// up loudly rather than silently choosing one branch.
fn tri_state<T>(value: Option<T>, clear: bool) -> lorvex_domain::Patch<T> {
    debug_assert!(
        !(value.is_some() && clear),
        "set and clear flags must not both be supplied; clap conflicts_with should have rejected this"
    );
    if clear {
        lorvex_domain::Patch::Clear
    } else {
        match value {
            Some(v) => lorvex_domain::Patch::Set(v),
            None => lorvex_domain::Patch::Unset,
        }
    }
}

pub(in crate::cli) fn translate_list(cmd: ListCmd) -> Command {
    Command::Lists(match cmd {
        ListCmd::Show(ListShowArgs { list_id, limit }) => ListsCommand::Show {
            list_id,
            limit,
            format: OutputFormat::default(),
        },
        ListCmd::Health(ListHealthArgs { limit }) => ListsCommand::Health {
            limit,
            format: OutputFormat::default(),
        },
        ListCmd::Create(ListCreateArgs {
            name,
            color,
            icon,
            description,
        }) => ListsCommand::Create {
            name: name.join(" "),
            color,
            icon,
            description,
            format: OutputFormat::default(),
        },
        ListCmd::Update(ListUpdateArgs {
            list_id,
            name,
            color,
            clear_color,
            icon,
            clear_icon,
            description,
            clear_description,
            ai_notes,
            clear_ai_notes,
        }) => ListsCommand::Update {
            list_id,
            name,
            // Collapse `(value, clear)` flag pairs into the canonical
            // `Patch<T>` tri-state. Clap's `conflicts_with` already
            // rejected `--color X --clear-color` so at most one branch fires.
            color: tri_state(color, clear_color),
            icon: tri_state(icon, clear_icon),
            description: tri_state(description, clear_description),
            ai_notes: tri_state(ai_notes, clear_ai_notes),
            format: OutputFormat::default(),
        },
        ListCmd::Delete(ListDeleteArgs { list_id }) => ListsCommand::Delete {
            list_id,
            format: OutputFormat::default(),
        },
    })
}
