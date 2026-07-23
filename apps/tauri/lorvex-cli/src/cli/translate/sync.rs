use super::super::args::{SyncCmd, SyncOutboxArgs};
use super::super::command::{Command, OutputFormat, SyncCommand};

pub(in crate::cli) fn translate_sync(cmd: &SyncCmd) -> Command {
    Command::Sync(match cmd {
        SyncCmd::Status => SyncCommand::Status {
            format: OutputFormat::default(),
        },
        SyncCmd::Outbox(SyncOutboxArgs { limit }) => SyncCommand::Outbox {
            limit: *limit,
            format: OutputFormat::default(),
        },
    })
}
