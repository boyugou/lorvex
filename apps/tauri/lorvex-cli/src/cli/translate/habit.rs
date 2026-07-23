use super::super::args::{
    HabitBatchCompleteArgs, HabitCmd, HabitCompleteArgs, HabitCreateArgs, HabitIdArgs,
    HabitReminderCmd, HabitReminderDeleteArgs, HabitReminderUpsertArgs, HabitStatsArgs,
    HabitUncompleteArgs, HabitUpdateArgs,
};
use super::super::clap_patch::{mutually_exclusive_bool, tri_state_clearable};
use super::super::command::{Command, HabitsCommand, OutputFormat};

pub(in crate::cli) fn translate_habit(cmd: HabitCmd) -> Command {
    Command::Habits(match cmd {
        HabitCmd::Create(HabitCreateArgs {
            name,
            icon,
            color,
            cue,
            frequency_type,
            weekday,
            per_period_target,
            day_of_month,
            target_count,
        }) => HabitsCommand::Create {
            name: name.join(" "),
            icon,
            color,
            cue,
            frequency_type,
            weekdays: weekday,
            per_period_target,
            day_of_month,
            target_count,
            format: OutputFormat::default(),
        },
        HabitCmd::Update(HabitUpdateArgs {
            habit_id,
            name,
            icon,
            clear_icon,
            color,
            clear_color,
            cue,
            clear_cue,
            frequency_type,
            weekday,
            per_period_target,
            day_of_month,
            target_count,
            archive,
            unarchive,
        }) => HabitsCommand::Update {
            habit_id,
            name,
            icon: tri_state_clearable(icon, clear_icon),
            color: tri_state_clearable(color, clear_color),
            cue: tri_state_clearable(cue, clear_cue),
            frequency_type,
            weekdays: weekday,
            per_period_target,
            day_of_month,
            target_count,
            archived: mutually_exclusive_bool(archive, unarchive),
            format: OutputFormat::default(),
        },
        HabitCmd::Delete(HabitIdArgs { habit_id }) => HabitsCommand::Delete {
            habit_id,
            format: OutputFormat::default(),
        },
        HabitCmd::Complete(HabitCompleteArgs {
            habit_id,
            date,
            note,
        }) => HabitsCommand::Complete {
            habit_id,
            date,
            note,
            format: OutputFormat::default(),
        },
        HabitCmd::BatchComplete(HabitBatchCompleteArgs { habit_ids, date }) => {
            HabitsCommand::BatchComplete {
                habit_ids,
                date,
                format: OutputFormat::default(),
            }
        }
        HabitCmd::Uncomplete(HabitUncompleteArgs { habit_id, date }) => HabitsCommand::Uncomplete {
            habit_id,
            date,
            format: OutputFormat::default(),
        },
        HabitCmd::Stats(HabitStatsArgs { habit_id, days }) => HabitsCommand::Stats {
            habit_id,
            days,
            format: OutputFormat::default(),
        },
        HabitCmd::Reminder(reminder) => translate_habit_reminder(reminder),
    })
}

fn translate_habit_reminder(cmd: HabitReminderCmd) -> HabitsCommand {
    match cmd {
        HabitReminderCmd::List => HabitsCommand::ReminderList {
            format: OutputFormat::default(),
        },
        HabitReminderCmd::Upsert(HabitReminderUpsertArgs {
            habit_id,
            reminder_time,
            policy_id,
            disabled,
        }) => HabitsCommand::ReminderUpsert {
            policy_id,
            habit_id,
            reminder_time,
            enabled: !disabled,
            format: OutputFormat::default(),
        },
        HabitReminderCmd::Delete(HabitReminderDeleteArgs { policy_id }) => {
            HabitsCommand::ReminderDelete {
                policy_id,
                format: OutputFormat::default(),
            }
        }
    }
}
