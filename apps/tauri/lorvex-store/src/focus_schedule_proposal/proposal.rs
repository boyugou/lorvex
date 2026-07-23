//! Top-level orchestrator + the private packing state machine that
//! interleaves calendar events with task slots inside the working
//! window.

use lorvex_domain::time::Date;
use lorvex_domain::CalendarAiAccessMode;
use rusqlite::Connection;

use crate::error::StoreError;
use crate::repositories::current_focus_items::query_focus_task_ids;

use super::queries::{load_task_candidates, load_working_hours};
use super::time_utils::{
    make_event_block, minutes_to_time_of_day, time_of_day_to_minutes, EventRange,
};
use super::types::{
    FocusScheduleBlock, FocusScheduleProposal, FocusScheduleSlot, FocusScheduleTask,
};

pub fn propose_focus_schedule(
    conn: &Connection,
    date: &str,
    anchor_timezone: &str,
    access_mode: CalendarAiAccessMode,
) -> Result<FocusScheduleProposal, StoreError> {
    let parsed_date = Date::parse(date)
        .map_err(|_| StoreError::Validation(format!("invalid focus schedule date: {date}")))?;
    let working_hours = load_working_hours(conn)?;
    let start_minutes = time_of_day_to_minutes(working_hours.start);
    let end_minutes = time_of_day_to_minutes(working_hours.end);
    if end_minutes < start_minutes {
        return Err(StoreError::Validation(
            "working_hours.end must be after working_hours.start".to_string(),
        ));
    }

    let focus_task_ids = query_focus_task_ids(conn, date)?;
    if focus_task_ids.is_empty() {
        return Err(StoreError::Validation(
            "no current focus set for this date; set focus tasks before proposing a schedule"
                .to_string(),
        ));
    }

    let tasks = load_task_candidates(conn, &focus_task_ids)?;
    if tasks.is_empty() {
        return Err(StoreError::Validation(
            "current focus has no open active tasks to schedule".to_string(),
        ));
    }

    let blocking = crate::calendar_timeline::get_day_blocking_ranges(
        conn,
        date,
        anchor_timezone,
        access_mode,
    )?;
    // perf: pre-size to the upper bound (every blocking range survives
    // the working-hours filter in the common case) so the filter+map
    // never re-grows the Vec.
    let mut event_ranges: Vec<EventRange> = Vec::with_capacity(blocking.len());
    // perf: fold total_event_minutes into the build pass so we don't
    // walk `event_ranges` twice (was filter+map+collect followed by
    // iter+map+sum). One pass also keeps the EventRange title/event_id
    // strings hot in cache while we're already touching them.
    let mut total_event_minutes: i64 = 0;
    for range in blocking {
        if range.end_minutes <= start_minutes || range.start_minutes >= end_minutes {
            continue;
        }
        let clipped_start = range.start_minutes.max(start_minutes);
        let clipped_end = range.end_minutes.min(end_minutes);
        total_event_minutes += (clipped_end - clipped_start).max(0);
        event_ranges.push(EventRange {
            start: range.start_minutes,
            end: range.end_minutes,
            title: range.title,
            event_id: range.canonical_event_id,
        });
    }
    let calendar_events_count = event_ranges.len();

    let mut state = ProposalState {
        event_ranges: &event_ranges,
        event_idx: 0,
        cursor: start_minutes,
        start_minutes,
        end_minutes,
        buffer_minutes: 10,
        // perf: each task contributes at most one slot + one task block
        // (+ optional buffer); pre-size to the upper bound so the
        // packing loop never re-grows.
        slots: Vec::with_capacity(tasks.len()),
        // upper bound: one task block + one buffer per task, plus one
        // event block per calendar event.
        blocks: Vec::with_capacity(tasks.len() * 2 + event_ranges.len()),
    };
    let mut unscheduled: Vec<FocusScheduleTask> = Vec::with_capacity(tasks.len());

    for task in tasks {
        let duration = task
            .estimated_minutes
            .filter(|value| *value > 0)
            .unwrap_or(30);
        state.flush_events();

        if state.cursor + duration > state.available_until() {
            if !state.try_schedule_later(&task, duration) {
                unscheduled.push(task);
            }
            continue;
        }

        state.place_task(&task, duration);
    }

    state.flush_remaining_events();
    state.blocks.sort_by_key(|block| block.start_time);

    Ok(FocusScheduleProposal {
        date: parsed_date,
        working_hours,
        total_minutes_available: end_minutes - start_minutes - total_event_minutes,
        calendar_events_count,
        slots: state.slots,
        blocks: state.blocks,
        unscheduled,
    })
}

struct ProposalState<'a> {
    event_ranges: &'a [EventRange],
    event_idx: usize,
    cursor: i64,
    start_minutes: i64,
    end_minutes: i64,
    buffer_minutes: i64,
    slots: Vec<FocusScheduleSlot>,
    blocks: Vec<FocusScheduleBlock>,
}

impl ProposalState<'_> {
    fn flush_events(&mut self) {
        while self.event_idx < self.event_ranges.len()
            && self.event_ranges[self.event_idx].start <= self.cursor
        {
            let event = &self.event_ranges[self.event_idx];
            let block_start = event.start.max(self.start_minutes);
            let block_end = event.end.min(self.end_minutes);
            if block_start < block_end {
                self.blocks
                    .push(make_event_block(event, block_start, block_end));
            }
            self.cursor = self.cursor.max(event.end);
            self.event_idx += 1;
        }
    }

    fn available_until(&self) -> i64 {
        let next = if self.event_idx < self.event_ranges.len() {
            self.event_ranges[self.event_idx].start
        } else {
            self.end_minutes
        };
        next.min(self.end_minutes)
    }

    fn place_task(&mut self, task: &FocusScheduleTask, duration: i64) {
        let start = minutes_to_time_of_day(self.cursor);
        let end = minutes_to_time_of_day(self.cursor + duration);
        self.slots.push(FocusScheduleSlot {
            task: task.clone(),
            start_time: start,
            end_time: end,
        });
        self.blocks.push(FocusScheduleBlock {
            block_type: "task".to_string(),
            start_time: start,
            end_time: end,
            task_id: Some(task.id.clone()),
            event_id: None,
            title: None,
        });
        self.cursor += duration;

        let available_until = self.available_until();
        if self.cursor + self.buffer_minutes <= available_until {
            let start_time = minutes_to_time_of_day(self.cursor);
            let end_time = minutes_to_time_of_day(self.cursor + self.buffer_minutes);
            self.blocks.push(FocusScheduleBlock {
                block_type: "buffer".to_string(),
                start_time,
                end_time,
                task_id: None,
                event_id: None,
                title: None,
            });
            self.cursor += self.buffer_minutes;
        }
    }

    fn try_schedule_later(&mut self, task: &FocusScheduleTask, duration: i64) -> bool {
        let mut probe_cursor = self.cursor;
        let mut probe_idx = self.event_idx;

        while probe_idx < self.event_ranges.len() {
            let event = &self.event_ranges[probe_idx];
            probe_cursor = probe_cursor.max(event.end);
            probe_idx += 1;

            let next_boundary = if probe_idx < self.event_ranges.len() {
                self.event_ranges[probe_idx].start
            } else {
                self.end_minutes
            };

            if probe_cursor + duration <= next_boundary.min(self.end_minutes) {
                for skipped_event in &self.event_ranges[self.event_idx..probe_idx] {
                    let block_start = skipped_event.start.max(self.start_minutes);
                    let block_end = skipped_event.end.min(self.end_minutes);
                    if block_start < block_end {
                        self.blocks
                            .push(make_event_block(skipped_event, block_start, block_end));
                    }
                }
                self.event_idx = probe_idx;
                self.cursor = probe_cursor;
                self.place_task(task, duration);
                return true;
            }
        }

        false
    }

    fn flush_remaining_events(&mut self) {
        while self.event_idx < self.event_ranges.len() {
            let event = &self.event_ranges[self.event_idx];
            let block_start = event.start.max(self.start_minutes);
            let block_end = event.end.min(self.end_minutes);
            if block_start < block_end {
                self.blocks
                    .push(make_event_block(event, block_start, block_end));
            }
            self.event_idx += 1;
        }
    }
}
