//! Public DTOs returned by the focus-schedule planner.
//!
//! Fields are `pub(crate)` so siblings inside this module can still
//! build them with `Struct { … }` literals, while external readers
//! (lorvex-cli, mcp-server) go through the public accessor methods.
//! The invariants the planner enforces — `end_minutes >= start_minutes`,
//! HH:MM-formatted times, contiguous blocks within working hours —
//! would be defeated if downstream callers could rebuild these structs
//! by hand with malformed strings (#3289).

use lorvex_domain::time::{Date, TimeOfDay};
use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct FocusScheduleWorkingHours {
    pub(crate) start: TimeOfDay,
    pub(crate) end: TimeOfDay,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct FocusScheduleTask {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: String,
    pub(crate) due_date: Option<Date>,
    pub(crate) planned_date: Option<Date>,
    pub(crate) priority: Option<i64>,
    pub(crate) list_id: String,
    pub(crate) estimated_minutes: Option<i64>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct FocusScheduleSlot {
    pub(crate) task: FocusScheduleTask,
    pub(crate) start_time: TimeOfDay,
    pub(crate) end_time: TimeOfDay,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct FocusScheduleBlock {
    pub(crate) block_type: String,
    pub(crate) start_time: TimeOfDay,
    pub(crate) end_time: TimeOfDay,
    pub(crate) task_id: Option<String>,
    pub(crate) event_id: Option<String>,
    pub(crate) title: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct FocusScheduleProposal {
    pub(crate) date: Date,
    pub(crate) working_hours: FocusScheduleWorkingHours,
    pub(crate) total_minutes_available: i64,
    pub(crate) calendar_events_count: usize,
    pub(crate) slots: Vec<FocusScheduleSlot>,
    pub(crate) blocks: Vec<FocusScheduleBlock>,
    pub(crate) unscheduled: Vec<FocusScheduleTask>,
}

impl FocusScheduleWorkingHours {
    pub const fn start(&self) -> TimeOfDay {
        self.start
    }
    pub const fn end(&self) -> TimeOfDay {
        self.end
    }
}

impl FocusScheduleTask {
    pub fn id(&self) -> &str {
        &self.id
    }
    pub fn title(&self) -> &str {
        &self.title
    }
    pub fn status(&self) -> &str {
        &self.status
    }
    pub const fn due_date(&self) -> Option<Date> {
        self.due_date
    }
    pub const fn planned_date(&self) -> Option<Date> {
        self.planned_date
    }
    pub const fn priority(&self) -> Option<i64> {
        self.priority
    }
    pub fn list_id(&self) -> &str {
        &self.list_id
    }
    pub const fn estimated_minutes(&self) -> Option<i64> {
        self.estimated_minutes
    }
}

impl FocusScheduleSlot {
    pub const fn task(&self) -> &FocusScheduleTask {
        &self.task
    }
    pub const fn start_time(&self) -> TimeOfDay {
        self.start_time
    }
    pub const fn end_time(&self) -> TimeOfDay {
        self.end_time
    }
}

impl FocusScheduleBlock {
    pub fn block_type(&self) -> &str {
        &self.block_type
    }
    pub const fn start_time(&self) -> TimeOfDay {
        self.start_time
    }
    pub const fn end_time(&self) -> TimeOfDay {
        self.end_time
    }
    pub fn task_id(&self) -> Option<&str> {
        self.task_id.as_deref()
    }
    pub fn event_id(&self) -> Option<&str> {
        self.event_id.as_deref()
    }
    pub fn title(&self) -> Option<&str> {
        self.title.as_deref()
    }
}

impl FocusScheduleProposal {
    pub const fn date(&self) -> Date {
        self.date
    }
    pub const fn working_hours(&self) -> &FocusScheduleWorkingHours {
        &self.working_hours
    }
    pub const fn total_minutes_available(&self) -> i64 {
        self.total_minutes_available
    }
    pub const fn calendar_events_count(&self) -> usize {
        self.calendar_events_count
    }
    pub fn slots(&self) -> &[FocusScheduleSlot] {
        &self.slots
    }
    pub fn blocks(&self) -> &[FocusScheduleBlock] {
        &self.blocks
    }
    pub fn unscheduled(&self) -> &[FocusScheduleTask] {
        &self.unscheduled
    }
}
