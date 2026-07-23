use crate::error::AppResult;

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
#[derive(Debug)]
pub(super) struct SourceTimeSemantics {
    pub(super) kind: &'static str,
    pub(super) tzid: Option<String>,
}

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub(super) fn resolve_source_time_semantics<F>(
    cached_tz: &mut Option<String>,
    all_day: bool,
    init_tz: F,
) -> AppResult<SourceTimeSemantics>
where
    F: FnOnce() -> AppResult<String>,
{
    if all_day {
        return Ok(SourceTimeSemantics {
            kind: "floating",
            tzid: None,
        });
    }

    if cached_tz.is_none() {
        *cached_tz = Some(init_tz()?);
    }

    Ok(SourceTimeSemantics {
        kind: "tzid",
        tzid: cached_tz.clone(),
    })
}
