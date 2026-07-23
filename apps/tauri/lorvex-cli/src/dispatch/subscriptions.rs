//! `lorvex subscription …` dispatcher.

use crate::cli::SubscriptionCommand;
use crate::commands::mutate::{
    run_subscription_add, run_subscription_list, run_subscription_refresh, run_subscription_remove,
    run_subscription_toggle,
};
use crate::error::CliError;

pub(super) fn dispatch_subscriptions(command: SubscriptionCommand) -> Result<(), CliError> {
    match command {
        SubscriptionCommand::List { format, verbose } => {
            println!("{}", run_subscription_list(format, verbose)?);
        }
        SubscriptionCommand::Add {
            url,
            name,
            color,
            format,
        } => {
            println!(
                "{}",
                run_subscription_add(name.as_deref(), &url, color.as_deref(), format)?
            );
        }
        SubscriptionCommand::Remove { id, format } => {
            println!("{}", run_subscription_remove(&id, format)?);
        }
        SubscriptionCommand::Toggle { id, format } => {
            println!("{}", run_subscription_toggle(&id, format)?);
        }
        SubscriptionCommand::Refresh { id, all, format } => {
            println!("{}", run_subscription_refresh(id.as_deref(), all, format)?);
        }
    }
    Ok(())
}
