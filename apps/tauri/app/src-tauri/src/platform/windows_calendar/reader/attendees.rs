#[cfg(target_os = "windows")]
pub(super) fn extract_windows_attendees(
    appt: &windows::ApplicationModel::Appointments::Appointment,
    local_id: &str,
) -> Option<String> {
    use windows::ApplicationModel::Appointments::*;
    let invitees = appt.Invitees().ok()?;
    // WinRT IVector::Size returns u32 natively. Stay
    // in u32 for the loop counter so the GetAt call never needs
    // a `usize as u32` truncating cast. The previous code cast
    // through `usize` to compute `count` and back to `u32` for
    // the index — harmless on 64-bit Windows today (usize >=
    // u32) but brittle if a future refactor introduced any
    // arithmetic that could overflow u32 in `usize` space.
    // Defensive cap: an aggregator-supplied appointment with a
    // hostile `Invitees().Size()` (e.g. millions of fake attendees
    // from a compromised Exchange ACL) would otherwise pre-allocate
    // unbounded memory before the per-invitee loop does any
    // filtering. The cap mirrors the ICS parser
    // (`MAX_ATTENDEES_PER_EVENT = 500`) so the attendee_shadow row
    // count stays bounded uniformly across native-calendar IPC and
    // ICS subscription.
    const MAX_WINDOWS_INVITEES: u32 =
        lorvex_workflow::calendar_subscription::parse::MAX_ATTENDEES_PER_EVENT as u32;
    let raw_count: u32 = invitees.Size().ok()?;
    if raw_count == 0 {
        return None;
    }
    let count = raw_count.min(MAX_WINDOWS_INVITEES);
    // When the cap kicks in, surface a diagnostic so a power-user
    // wondering "why does my Outlook distribution-list meeting only
    // show the first 1024 attendees?" can find the answer in
    // Settings → Diagnostics instead of reading the source. The cap
    // itself is a memory-safety floor against hostile aggregators,
    // so we don't relax it — we only document it.
    if raw_count > MAX_WINDOWS_INVITEES {
        if let Ok(conn) = crate::db::get_conn() {
            let _ = crate::commands::diagnostics::append_error_log_internal(
                &conn,
                "platform.windows_calendar",
                &format!(
                    "Windows appointment {local_id} has {raw_count} invitees; \
                     truncating to {MAX_WINDOWS_INVITEES} to bound memory. The \
                     remaining {} attendees are not shadowed into \
                     provider_calendar_events.",
                    raw_count - MAX_WINDOWS_INVITEES
                ),
                None,
                Some("warn".to_string()),
            );
        }
    }
    let mut arr: Vec<serde_json::Value> = Vec::with_capacity(count as usize);
    for i in 0..count {
        if let Ok(invitee) = invitees.GetAt(i) {
            let email = invitee.Address().map(|s| s.to_string()).unwrap_or_default();
            if email.is_empty() {
                continue;
            }
            let mut obj = serde_json::Map::new();
            obj.insert("email".to_string(), serde_json::Value::String(email));
            // Map AppointmentParticipantResponse to status string.
            //
            // Log the raw enum once per appointment so the next SDK
            // bump knows which variant needs first-class mapping. A
            // bare catch-all `_ => "needs-action"` would silently
            // absorb any future SDK enum variant (e.g. a new
            // `Delegated` value the broker forwards verbatim) and any
            // aggregator-supplied historical value. The visible
            // behavior stays `needs-action` as the conservative
            // fallback the renderer already understands.
            if let Ok(response) = invitee.Response() {
                let status = match response {
                    AppointmentParticipantResponse::Accepted => "accepted",
                    AppointmentParticipantResponse::Declined => "declined",
                    AppointmentParticipantResponse::Tentative => "tentative",
                    other => {
                        // The intentional sentinels — `None` (no
                        // response yet) and `Unknown` (broker doesn't
                        // know) — both match RFC 5545's
                        // `NEEDS-ACTION` semantically and get the
                        // same string. A bare catch-all `_ =>
                        // "needs-action"` would silently absorb any
                        // future SDK enum value the broker forwards
                        // verbatim (e.g. a hypothetical `Delegated`),
                        // so the raw enum value is logged when it
                        // falls outside the
                        // canonical four (Accepted / Declined /
                        // Tentative / None / Unknown) so the next
                        // SDK bump knows which variant needs
                        // first-class mapping; the conservative
                        // visible fallback is unchanged. Filter
                        // by raw discriminant to avoid log
                        // pressure from the canonical "no
                        // response yet" cases.
                        const NONE: i32 = 0;
                        const UNKNOWN: i32 = 4;
                        if !matches!(other.0, NONE | UNKNOWN) {
                            if let Ok(conn) = crate::db::get_conn() {
                                let _ = crate::commands::diagnostics::append_error_log_internal(
                                    &conn,
                                    "platform.windows_calendar",
                                    &format!(
                                        "Windows invitee carried unknown \
                                         AppointmentParticipantResponse variant \
                                         ({other:?}) for appointment {local_id}; falling \
                                         back to `needs-action`."
                                    ),
                                    None,
                                    Some("warn".to_string()),
                                );
                            }
                        }
                        "needs-action"
                    }
                };
                obj.insert(
                    "status".to_string(),
                    serde_json::Value::String(status.to_string()),
                );
            }
            arr.push(serde_json::Value::Object(obj));
        }
    }
    if arr.is_empty() {
        None
    } else {
        serde_json::to_string(&arr).ok()
    }
}
