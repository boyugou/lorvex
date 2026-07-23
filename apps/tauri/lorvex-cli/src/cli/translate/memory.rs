use super::super::args::{
    MemoryCmd, MemoryHistoryArgs, MemoryKeyArgs, MemoryRestoreArgs, MemoryShowArgs, MemoryWriteArgs,
};
use super::super::command::{Command, MemoryCommand, OutputFormat};

pub(in crate::cli) fn translate_memory(cmd: MemoryCmd) -> Command {
    Command::Memory(match cmd {
        MemoryCmd::List => MemoryCommand::List {
            format: OutputFormat::default(),
        },
        MemoryCmd::Show(MemoryShowArgs { key }) => MemoryCommand::Show {
            key,
            format: OutputFormat::default(),
        },
        MemoryCmd::Write(MemoryWriteArgs { key, content }) => MemoryCommand::Write {
            key,
            content: content.join(" "),
            format: OutputFormat::default(),
        },
        MemoryCmd::Delete(MemoryKeyArgs { key }) => MemoryCommand::Delete {
            key,
            format: OutputFormat::default(),
        },
        MemoryCmd::History(MemoryHistoryArgs { key, limit }) => MemoryCommand::History {
            key,
            limit,
            format: OutputFormat::default(),
        },
        MemoryCmd::Restore(MemoryRestoreArgs { revision_id }) => MemoryCommand::Restore {
            revision_id,
            format: OutputFormat::default(),
        },
    })
}
