/// Tri-state archive intent for a habit update patch.
///
/// `Some(true)` meant "set archived = true", `Some(false)` meant
/// "unarchive", and `None` meant "leave unchanged". The shape was
/// readable but consumers had to remember the convention at every
/// match site, and `Option<Option<bool>>` was tempting whenever a
/// field genuinely needed a tri-state distinction (it doesn't here).
/// Replacing it with an explicit enum lets callers exhaustive-match
/// on the three valid intents, eliminating "did I forget the unarchive
/// branch?" review noise.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ArchiveAction {
    /// The patch did not specify an archive intent. Leave the
    /// existing `archived` flag alone.
    #[default]
    NoChange,
    /// Set `archived = true` (archive the habit).
    Archive,
    /// Set `archived = false` (un-archive the habit).
    Unarchive,
}

impl ArchiveAction {
    /// Construct from the boundary `Option<bool>` shape that
    /// clap / serde produce at MCP and CLI argument boundaries.
    /// `Some(true) → Archive`, `Some(false) → Unarchive`, `None →
    /// NoChange`.
    pub const fn from_optional_bool(value: Option<bool>) -> Self {
        match value {
            None => Self::NoChange,
            Some(true) => Self::Archive,
            Some(false) => Self::Unarchive,
        }
    }

    /// Returns the resulting `archived` bool when the patch carries
    /// a change, or `None` when the patch leaves the flag alone. SQL
    /// bind sites that bind a bool only when the patch sets archived
    /// can use this directly.
    pub const fn target_value(self) -> Option<bool> {
        match self {
            Self::NoChange => None,
            Self::Archive => Some(true),
            Self::Unarchive => Some(false),
        }
    }

    /// True iff the patch carries an archive change of any kind.
    pub const fn is_present(self) -> bool {
        !matches!(self, Self::NoChange)
    }
}
