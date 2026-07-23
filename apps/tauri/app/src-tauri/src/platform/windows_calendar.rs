//! Windows native calendar reading — reads from Windows Appointments API.
//!
//! Uses the `windows` crate to access `Windows.ApplicationModel.Appointments`
//! and mirrors events into `provider_calendar_events` with
//! `provider_kind = 'windows_appointments'`.

pub mod reader;
