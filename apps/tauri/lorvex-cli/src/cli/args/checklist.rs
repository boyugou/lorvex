//! clap arg structs for the checklist mutation surface
//! (`add` / `update` / `toggle` / `remove` / `reorder`). The MCP server
//! exposes these as five distinct tools (`add_task_checklist_item`,
//! `update_task_checklist_item`, etc.); the CLI groups them under a
//! single `checklist` subcommand for ergonomics.

use clap::{Args, Subcommand};

use super::super::parsers::{parse_checklist_item_id, parse_task_id};

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum ChecklistCmd {
    /// Append or insert one checklist item on a task (mirrors MCP
    /// `add_task_checklist_item`).
    Add(ChecklistAddArgs),
    /// Update one checklist item's text (mirrors MCP
    /// `update_task_checklist_item`).
    Update(ChecklistUpdateArgs),
    /// Set one checklist item's completed state (mirrors MCP
    /// `toggle_task_checklist_item`).
    Toggle(ChecklistToggleArgs),
    /// Remove one checklist item by id (mirrors MCP
    /// `remove_task_checklist_item`).
    Remove(ChecklistRemoveArgs),
    /// Reorder a task's checklist (mirrors MCP
    /// `reorder_task_checklist_items`). Pass every existing item id in
    /// the desired order.
    Reorder(ChecklistReorderArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ChecklistAddArgs {
    /// Target task id.
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// Checklist item text (one or more words joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) text: Vec<String>,
    /// Optional zero-based insert position; omit to append.
    /// Zero is valid (insert at the head); the MCP contract bounds the
    /// upper end at the existing item count.
    #[arg(long = "position")]
    pub(in crate::cli) position: Option<u32>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ChecklistUpdateArgs {
    /// Checklist item id.
    #[arg(value_parser = parse_checklist_item_id)]
    pub(in crate::cli) item_id: String,
    /// Updated checklist item text.
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) text: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ChecklistToggleArgs {
    /// Checklist item id.
    #[arg(value_parser = parse_checklist_item_id)]
    pub(in crate::cli) item_id: String,
    /// Force the completed state to true.
    #[arg(
        long = "completed",
        conflicts_with = "uncompleted",
        required_unless_present = "uncompleted"
    )]
    pub(in crate::cli) completed: bool,
    /// Force the completed state to false.
    #[arg(long = "uncompleted")]
    pub(in crate::cli) uncompleted: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ChecklistRemoveArgs {
    /// Checklist item id.
    #[arg(value_parser = parse_checklist_item_id)]
    pub(in crate::cli) item_id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ChecklistReorderArgs {
    /// Target task id.
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// Ordered checklist item ids; must contain every existing item.
    #[arg(required = true, num_args = 1.., value_parser = parse_checklist_item_id)]
    pub(in crate::cli) item_ids: Vec<String>,
}
