use super::*;

pub(super) fn calendar_write_tx(
    conn: &mut Connection,
) -> Result<rusqlite::Transaction<'_>, crate::error::CliError> {
    Ok(conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?)
}
