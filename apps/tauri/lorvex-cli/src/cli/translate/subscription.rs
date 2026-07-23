//! Translation from the clap subscription parse tree into the
//! dispatch [`SubscriptionCommand`].

use super::super::args::{
    SubscriptionAddArgs, SubscriptionCmd, SubscriptionIdArgs, SubscriptionListArgs,
    SubscriptionRefreshArgs,
};
use super::super::command::{Command, OutputFormat, SubscriptionCommand};

pub(in crate::cli) fn translate_subscription(cmd: SubscriptionCmd) -> Command {
    Command::Subscription(match cmd {
        SubscriptionCmd::List(SubscriptionListArgs { verbose }) => SubscriptionCommand::List {
            format: OutputFormat::default(),
            verbose,
        },
        SubscriptionCmd::Add(SubscriptionAddArgs { url, name, color }) => {
            SubscriptionCommand::Add {
                url,
                name,
                color,
                format: OutputFormat::default(),
            }
        }
        SubscriptionCmd::Remove(SubscriptionIdArgs { id }) => SubscriptionCommand::Remove {
            id,
            format: OutputFormat::default(),
        },
        SubscriptionCmd::Toggle(SubscriptionIdArgs { id }) => SubscriptionCommand::Toggle {
            id,
            format: OutputFormat::default(),
        },
        SubscriptionCmd::Refresh(SubscriptionRefreshArgs { id, all }) => {
            SubscriptionCommand::Refresh {
                id,
                all,
                format: OutputFormat::default(),
            }
        }
    })
}
