use crate::contract::{LogLevelFilter, LogSourceFilter};

pub(crate) fn merge_requested_levels(
    level: Option<LogLevelFilter>,
    levels: Option<Vec<LogLevelFilter>>,
) -> Vec<LogLevelFilter> {
    let mut merged: Vec<LogLevelFilter> = Vec::new();
    if let Some(level) = level {
        merged.push(level);
        if let Some(levels) = levels {
            merged.extend(levels);
        }
    } else if let Some(levels) = levels {
        merged.extend(levels);
    } else {
        merged.extend([
            LogLevelFilter::Debug,
            LogLevelFilter::Info,
            LogLevelFilter::Warn,
            LogLevelFilter::Error,
        ]);
    }
    merged
}

pub(crate) fn merge_requested_sources(
    source: Option<LogSourceFilter>,
    sources: Option<Vec<LogSourceFilter>>,
) -> Vec<LogSourceFilter> {
    let mut merged: Vec<LogSourceFilter> = Vec::new();
    if let Some(source) = source {
        merged.push(source);
        if let Some(sources) = sources {
            merged.extend(sources);
        }
    } else if let Some(sources) = sources {
        merged.extend(sources);
    } else {
        merged.extend([
            LogSourceFilter::ErrorLog,
            LogSourceFilter::AiChangelog,
            LogSourceFilter::SyncOutbox,
        ]);
    }
    merged
}
