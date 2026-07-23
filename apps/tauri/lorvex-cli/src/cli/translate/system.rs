//! Cross-cutting system commands: setup, doctor, status, changelog,
//! export/import, tui, mcp, completions, error-logs. Every
//! arm here funnels into `Command::System`.

use clap_complete::Shell;

use super::super::args::{
    ChangelogArgs, ErrorLogsArgs, McpCmd, PathArgs, SetupCompleteArgs, TuiArgs,
};
use super::super::command::{Command, McpInstallTarget, OutputFormat, SystemCommand};

pub(in crate::cli) const fn translate_setup(install_mcp_for: Option<McpInstallTarget>) -> Command {
    Command::System(SystemCommand::Setup {
        install_target: install_mcp_for,
    })
}

pub(in crate::cli) fn translate_doctor() -> Command {
    Command::System(SystemCommand::Doctor {
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_status() -> Command {
    Command::System(SystemCommand::Status {
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_changelog(args: ChangelogArgs) -> Command {
    let ChangelogArgs {
        limit,
        entity_type,
        operation,
        entity_id,
        since,
    } = args;
    Command::System(SystemCommand::Changelog {
        limit,
        entity_type,
        operation,
        entity_id,
        since,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_export(args: PathArgs) -> Command {
    let PathArgs { path } = args;
    Command::System(SystemCommand::Export {
        output_path: path,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_import(args: PathArgs) -> Command {
    let PathArgs { path } = args;
    Command::System(SystemCommand::Import {
        input_path: path,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_setup_status() -> Command {
    Command::System(SystemCommand::SetupStatus {
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_setup_complete(args: SetupCompleteArgs) -> Command {
    let SetupCompleteArgs { summary } = args;
    Command::System(SystemCommand::SetupComplete {
        summary: summary.join(" "),
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) const fn translate_tui(args: &TuiArgs) -> Command {
    if args.watch {
        Command::System(SystemCommand::TuiWatch)
    } else {
        Command::System(SystemCommand::Tui)
    }
}

pub(in crate::cli) const fn translate_mcp(cmd: &McpCmd) -> Command {
    match cmd {
        McpCmd::Serve => Command::System(SystemCommand::McpServe),
        McpCmd::Install { target } => {
            Command::System(SystemCommand::McpInstall { target: *target })
        }
    }
}

pub(in crate::cli) const fn translate_completions(shell: Shell) -> Command {
    Command::System(SystemCommand::Completions { shell })
}

pub(in crate::cli) fn translate_error_logs(args: ErrorLogsArgs) -> Command {
    let ErrorLogsArgs { source, limit } = args;
    Command::System(SystemCommand::ErrorLogs {
        source,
        limit,
        format: OutputFormat::default(),
    })
}
