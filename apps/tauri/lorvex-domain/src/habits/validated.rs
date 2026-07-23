use crate::validation::{
    validate_hex_color_field, validate_string_length, ValidationError, MAX_HABIT_CUE_LENGTH,
    MAX_SHORT_TEXT_LENGTH, MAX_TITLE_LENGTH,
};
use crate::Patch;

use super::archive::ArchiveAction;
use super::cadence::HabitCadence;
use super::draft::{HabitCreateDraft, HabitUpdateDraft};

/// Validated, ready-to-persist habit-create payload. Constructed only via
/// [`validate_habit_create_draft`] so the cadence consistency invariants
/// and length / color / lookup_key rules cannot be bypassed by direct
/// field assignment (#3289 / #3300).
///
/// Fields are private; readers use the borrow accessors (`name()`, `icon()`,
/// …) for SQL bind sites, and consuming destructure goes through
/// [`ValidatedHabitCreate::into_parts`] which yields a plain
/// [`HabitCreateParts`] data carrier whose public fields can then be moved
/// individually. SQL bind sites that need the typed cadence columns
/// (`frequency_type`, `per_period_target`, `day_of_month`) plus the
/// `habit_weekdays` child render the cadence through
/// [`HabitCadence::to_fields`] at the bind seam.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidatedHabitCreate {
    name: String,
    icon: Option<String>,
    color: Option<String>,
    cue: Option<String>,
    frequency: HabitCadence,
    target_count: i64,
    lookup_key: String,
}

/// Plain data-carrier shape produced by [`ValidatedHabitCreate::into_parts`].
/// Public fields here are intentional — the validation invariants live on
/// the wrapper, and once the caller has destructured into `HabitCreateParts`
/// the values are owned and moveable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HabitCreateParts {
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub cue: Option<String>,
    pub frequency: HabitCadence,
    pub target_count: i64,
    pub lookup_key: String,
}

impl ValidatedHabitCreate {
    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn icon(&self) -> Option<&str> {
        self.icon.as_deref()
    }

    pub fn color(&self) -> Option<&str> {
        self.color.as_deref()
    }

    pub fn cue(&self) -> Option<&str> {
        self.cue.as_deref()
    }

    pub const fn frequency(&self) -> &HabitCadence {
        &self.frequency
    }

    pub const fn target_count(&self) -> i64 {
        self.target_count
    }

    pub fn lookup_key(&self) -> &str {
        &self.lookup_key
    }

    /// Destructure into a plain [`HabitCreateParts`] data carrier. The
    /// validated wrapper is consumed; callers that need to move individual
    /// fields out (e.g. into a `Vec<Box<dyn ToSql>>` bind list) destructure
    /// the returned struct normally.
    pub fn into_parts(self) -> HabitCreateParts {
        HabitCreateParts {
            name: self.name,
            icon: self.icon,
            color: self.color,
            cue: self.cue,
            frequency: self.frequency,
            target_count: self.target_count,
            lookup_key: self.lookup_key,
        }
    }
}

/// Validated habit-update patch. Constructed only via
/// [`validate_habit_update_draft`]; fields are sealed behind accessors and
/// [`ValidatedHabitUpdate::into_parts`] so the per-field length / cadence /
/// color / lookup_key rules the validator enforces cannot be defeated by
/// direct field assignment (#3289 / #3300).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidatedHabitUpdate {
    name: Option<String>,
    icon: Patch<String>,
    color: Patch<String>,
    cue: Patch<String>,
    frequency: Option<HabitCadence>,
    target_count: Option<i64>,
    archived: ArchiveAction,
    lookup_key: Option<String>,
}

/// Plain data-carrier shape produced by [`ValidatedHabitUpdate::into_parts`].
/// See [`HabitCreateParts`] for the rationale.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HabitUpdateParts {
    pub name: Option<String>,
    pub icon: Patch<String>,
    pub color: Patch<String>,
    pub cue: Patch<String>,
    pub frequency: Option<HabitCadence>,
    pub target_count: Option<i64>,
    pub archived: ArchiveAction,
    pub lookup_key: Option<String>,
}

impl ValidatedHabitUpdate {
    pub fn name(&self) -> Option<&str> {
        self.name.as_deref()
    }

    /// Tri-state accessor for the `icon` patch field.
    /// `Patch::Unset` = leave alone, `Patch::Clear` = clear, `Patch::Set(_)` = set.
    pub fn icon(&self) -> Patch<&str> {
        self.icon.as_deref()
    }

    pub fn color(&self) -> Patch<&str> {
        self.color.as_deref()
    }

    pub fn cue(&self) -> Patch<&str> {
        self.cue.as_deref()
    }

    /// `None` = leave cadence alone; `Some(_)` = replace entirely.
    pub const fn frequency(&self) -> Option<&HabitCadence> {
        self.frequency.as_ref()
    }

    pub const fn target_count(&self) -> Option<i64> {
        self.target_count
    }

    pub const fn archived(&self) -> ArchiveAction {
        self.archived
    }

    pub fn lookup_key(&self) -> Option<&str> {
        self.lookup_key.as_deref()
    }

    /// Destructure into a plain [`HabitUpdateParts`] data carrier. Callers
    /// that move individual `Option<String>` fields into a SQL bind list
    /// destructure the returned struct.
    pub fn into_parts(self) -> HabitUpdateParts {
        HabitUpdateParts {
            name: self.name,
            icon: self.icon,
            color: self.color,
            cue: self.cue,
            frequency: self.frequency,
            target_count: self.target_count,
            archived: self.archived,
            lookup_key: self.lookup_key,
        }
    }
}

pub fn validate_habit_create_draft(
    draft: HabitCreateDraft<'_>,
) -> Result<ValidatedHabitCreate, ValidationError> {
    let name = normalize_habit_name(draft.name)?;
    let icon = normalize_optional_habit_text(draft.icon, "icon", MAX_SHORT_TEXT_LENGTH)?;
    let color = normalize_optional_habit_color(draft.color)?;
    let cue = normalize_optional_habit_text(draft.cue, "cue", MAX_HABIT_CUE_LENGTH)?;
    // A cadence omitted at the boundary defaults to Daily.
    let frequency = draft.frequency.unwrap_or(HabitCadence::Daily);
    let target_count = normalize_habit_target_count(draft.target_count);
    let lookup_key = crate::tag::normalize_lookup_key(&name);

    Ok(ValidatedHabitCreate {
        name,
        icon,
        color,
        cue,
        frequency,
        target_count,
        lookup_key,
    })
}

pub fn validate_habit_update_draft(
    draft: HabitUpdateDraft<'_>,
) -> Result<ValidatedHabitUpdate, ValidationError> {
    let name = draft.name.map(normalize_habit_name).transpose()?;
    let icon = normalize_optional_patch_text(draft.icon, "icon", MAX_SHORT_TEXT_LENGTH)?;
    let color = normalize_optional_patch_color(draft.color)?;
    let cue = normalize_optional_patch_text(draft.cue, "cue", MAX_HABIT_CUE_LENGTH)?;
    let target_count = draft.target_count.map(|raw| raw.max(1));
    let lookup_key = name.as_deref().map(crate::tag::normalize_lookup_key);

    Ok(ValidatedHabitUpdate {
        name,
        icon,
        color,
        cue,
        frequency: draft.frequency,
        target_count,
        archived: draft.archived,
        lookup_key,
    })
}

fn normalize_habit_name(value: &str) -> Result<String, ValidationError> {
    let sanitized = crate::sanitize_user_text(value);
    let trimmed = sanitized.trim();
    if trimmed.is_empty() || crate::validation::is_visually_empty(trimmed) {
        return Err(ValidationError::Empty("habit name"));
    }
    validate_string_length(trimmed, "name", MAX_TITLE_LENGTH)?;
    Ok(trimmed.to_string())
}

fn normalize_optional_habit_text(
    value: Option<&str>,
    field: &'static str,
    max: usize,
) -> Result<Option<String>, ValidationError> {
    let Some(value) = value else {
        return Ok(None);
    };
    let sanitized = crate::sanitize_user_text(value);
    let trimmed = sanitized.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    validate_string_length(trimmed, field, max)?;
    Ok(Some(trimmed.to_string()))
}

fn normalize_optional_patch_text(
    value: Patch<&str>,
    field: &'static str,
    max: usize,
) -> Result<Patch<String>, ValidationError> {
    match value {
        Patch::Unset => Ok(Patch::Unset),
        Patch::Clear => Ok(Patch::Clear),
        Patch::Set(v) => match normalize_optional_habit_text(Some(v), field, max)? {
            Some(s) => Ok(Patch::Set(s)),
            None => Ok(Patch::Clear),
        },
    }
}

fn normalize_optional_habit_color(value: Option<&str>) -> Result<Option<String>, ValidationError> {
    let color = normalize_optional_habit_text(value, "color", MAX_SHORT_TEXT_LENGTH)?;
    if let Some(color) = color.as_deref() {
        validate_hex_color_field(color, "color")?;
    }
    Ok(color)
}

fn normalize_optional_patch_color(value: Patch<&str>) -> Result<Patch<String>, ValidationError> {
    match value {
        Patch::Unset => Ok(Patch::Unset),
        Patch::Clear => Ok(Patch::Clear),
        Patch::Set(v) => match normalize_optional_habit_color(Some(v))? {
            Some(s) => Ok(Patch::Set(s)),
            None => Ok(Patch::Clear),
        },
    }
}

fn normalize_habit_target_count(value: Option<i64>) -> i64 {
    value.unwrap_or(1).max(1)
}
