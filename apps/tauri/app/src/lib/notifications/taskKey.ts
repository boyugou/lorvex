/// Dedup key for a pending reminder notification. Includes `reminder_at`
/// so that when a reminder is rescheduled (locally or via remote sync
/// resetting `task_reminder_delivery_state`), the new key differs from
/// the already-notified one and the rescheduled instance fires. Keying
/// on `id` alone (the behavior) caused users to miss every
/// rescheduled reminder for the process lifetime.
export function reminderNotificationKey(
  reminder: { id: string; reminder_at: string },
): string {
  return `${reminder.id}@${reminder.reminder_at}`;
}
