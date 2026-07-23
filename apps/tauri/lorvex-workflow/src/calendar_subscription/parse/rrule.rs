use super::IcsParseWarning;

pub fn rrule_to_json(raw: &str) -> Option<String> {
    lorvex_domain::calendar_ics::parse_ics_rrule_to_recurrence_json(raw)
}

pub fn rrule_to_json_with_warnings(
    raw: &str,
    warnings: &mut Vec<IcsParseWarning>,
) -> Option<String> {
    let mut domain_warnings = Vec::new();
    let recurrence = lorvex_domain::calendar_ics::parse_ics_rrule_to_recurrence_json_with_warnings(
        raw,
        &mut domain_warnings,
    );
    warnings.extend(
        domain_warnings
            .into_iter()
            .map(|warning| IcsParseWarning::new(warning.message, warning.details)),
    );
    recurrence
}
