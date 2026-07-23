use super::*;
use clap_complete::Shell;

mod calendar;
mod focus;
mod habit;
mod list;
mod memory;
mod misc;
mod review;
mod task;
mod workflow;

pub(super) fn parse(args: &[&str]) -> Command {
    CliArgs::parse(args.iter().map(std::string::ToString::to_string).collect()).command
}

pub(super) fn try_parse(args: &[&str]) -> Result<Command, clap::Error> {
    CliArgs::try_parse(args.iter().map(std::string::ToString::to_string).collect())
        .map(|cli| cli.command)
}
