use super::super::args::{
    CalendarBatchCreateArgs, CalendarCmd, CalendarCreateArgs, CalendarExceptionArgs,
    CalendarExportIcsArgs, CalendarLinkArgs, CalendarProviderLinkArgs, CalendarSearchArgs,
    CalendarShowArgs, CalendarTaskLinksArgs, CalendarUnlinkArgs, CalendarUpdateArgs, LimitArgs,
};
use super::super::clap_patch::tri_state_clearable;
use super::super::command::{AttendeesPatch, CalendarCommand, Command, OutputFormat};

pub(in crate::cli) fn translate_calendar(cmd: CalendarCmd) -> Command {
    Command::Calendar(match cmd {
        CalendarCmd::List(LimitArgs { limit }) => CalendarCommand::List {
            limit,
            format: OutputFormat::default(),
        },
        CalendarCmd::Show(CalendarShowArgs { event_id }) => CalendarCommand::Show {
            event_id,
            format: OutputFormat::default(),
        },
        CalendarCmd::Today => CalendarCommand::Today {
            format: OutputFormat::default(),
        },
        CalendarCmd::Create(args) => {
            let CalendarCreateArgs {
                title,
                start_date,
                start_time,
                end_date,
                end_time,
                all_day,
                description,
                location,
                url,
                color,
                recurrence,
                timezone,
                event_type,
                person_name,
            } = *args;
            CalendarCommand::Create {
                title: title.join(" "),
                start_date,
                start_time,
                end_date,
                end_time,
                all_day,
                description,
                location,
                url,
                color,
                recurrence,
                timezone,
                event_type,
                person_name,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::BatchCreate(CalendarBatchCreateArgs { events_json }) => {
            CalendarCommand::BatchCreate {
                events_json,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::Update(args) => {
            let CalendarUpdateArgs {
                event_id,
                title,
                start_date,
                start_time,
                clear_start_time,
                end_date,
                clear_end_date,
                end_time,
                clear_end_time,
                all_day,
                timed,
                description,
                clear_description,
                location,
                clear_location,
                url,
                clear_url,
                color,
                clear_color,
                recurrence,
                clear_recurrence,
                timezone,
                clear_timezone,
                event_type,
                clear_event_type,
                person_name,
                clear_person_name,
                attendees_json,
                clear_attendees,
            } = *args;
            let attendees = if clear_attendees {
                AttendeesPatch::Clear
            } else if let Some(raw) = attendees_json {
                AttendeesPatch::Json(raw)
            } else {
                AttendeesPatch::Unset
            };
            CalendarCommand::Update {
                event_id,
                title,
                start_date,
                start_time: tri_state_clearable(start_time, clear_start_time),
                end_date: tri_state_clearable(end_date, clear_end_date),
                end_time: tri_state_clearable(end_time, clear_end_time),
                all_day: if all_day {
                    Some(true)
                } else if timed {
                    Some(false)
                } else {
                    None
                },
                description: tri_state_clearable(description, clear_description),
                location: tri_state_clearable(location, clear_location),
                url: tri_state_clearable(url, clear_url),
                color: tri_state_clearable(color, clear_color),
                recurrence: tri_state_clearable(recurrence, clear_recurrence),
                timezone: tri_state_clearable(timezone, clear_timezone),
                event_type: tri_state_clearable(event_type, clear_event_type),
                person_name: tri_state_clearable(person_name, clear_person_name),
                attendees,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::Delete(CalendarShowArgs { event_id }) => CalendarCommand::Delete {
            event_id,
            format: OutputFormat::default(),
        },
        CalendarCmd::Link(CalendarLinkArgs { event_id, task_ids }) => CalendarCommand::Link {
            event_id,
            task_ids,
            format: OutputFormat::default(),
        },
        CalendarCmd::Unlink(CalendarUnlinkArgs { event_id, task_id }) => CalendarCommand::Unlink {
            event_id,
            task_id,
            format: OutputFormat::default(),
        },
        CalendarCmd::LinksForTask(CalendarTaskLinksArgs { task_id }) => {
            CalendarCommand::LinksForTask {
                task_id,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::LinksForEvent(CalendarShowArgs { event_id }) => {
            CalendarCommand::LinksForEvent {
                event_id,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::AddException(CalendarExceptionArgs { event_id, date }) => {
            CalendarCommand::AddException {
                event_id,
                date,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::RemoveException(CalendarExceptionArgs { event_id, date }) => {
            CalendarCommand::RemoveException {
                event_id,
                date,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::ProviderLink(CalendarProviderLinkArgs {
            task_id,
            provider_kind,
            provider_scope,
            provider_event_key,
        }) => CalendarCommand::ProviderLink {
            task_id,
            provider_kind,
            provider_scope,
            provider_event_key,
            format: OutputFormat::default(),
        },
        CalendarCmd::ProviderUnlink(CalendarProviderLinkArgs {
            task_id,
            provider_kind,
            provider_scope,
            provider_event_key,
        }) => CalendarCommand::ProviderUnlink {
            task_id,
            provider_kind,
            provider_scope,
            provider_event_key,
            format: OutputFormat::default(),
        },
        CalendarCmd::ProviderLinksForTask(CalendarTaskLinksArgs { task_id }) => {
            CalendarCommand::ProviderLinksForTask {
                task_id,
                format: OutputFormat::default(),
            }
        }
        CalendarCmd::ExportIcs(CalendarExportIcsArgs { from, to }) => CalendarCommand::ExportIcs {
            from,
            to,
            format: OutputFormat::default(),
        },
        CalendarCmd::Search(CalendarSearchArgs {
            query,
            from,
            to,
            limit,
        }) => CalendarCommand::Search {
            query: query.join(" "),
            from,
            to,
            limit,
            format: OutputFormat::default(),
        },
    })
}
