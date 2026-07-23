use std::sync::LazyLock;

/// Reserved memory key for the human-owned notes block.
pub const MEMORY_KEY_NOTES_FOR_AI: &str = "notes_for_ai";

/// Normalize a memory key for machine equality.
///
/// Memory keys are structural natural keys, so this intentionally
/// does not casefold, NFKC-normalize, or collapse internal visible
/// whitespace. It only applies the shared user-text hygiene pass
/// (strip dangerous invisible controls + NFC) and trims boundary
/// whitespace so equivalent user/MCP/CLI arguments hit the same row.
pub fn normalize_memory_key(key: &str) -> String {
    crate::sanitize_user_text(key).trim().to_string()
}

/// Maximum length (in bytes) of a memory entry's content. Enforced at
/// MCP write time (mcp-server) and on sync apply (lorvex-sync). Also
/// enforced by the Tauri command-layer validator. See #2429.
pub const MAX_MEMORY_CONTENT_LENGTH: usize = 100_000;

/// Suffix appended to memory content that exceeded
/// [`MAX_MEMORY_CONTENT_LENGTH`] on sync apply. Serves as a visible
/// marker for the receiving assistant that the peer tried to exceed
/// the cap.
///
/// Built once at first access via `LazyLock<String>` from
/// [`MAX_MEMORY_CONTENT_LENGTH`] so the byte-cap literal is the
/// single source of truth. Hard-coding the literal inside the
/// sentinel string would let a future bump to the cap ship a
/// sentinel that lies about the actual cap if `cargo test -p
/// lorvex-domain` weren't run.
pub static MEMORY_TRUNCATION_SENTINEL: LazyLock<String> = LazyLock::new(|| {
    format!("\n\n... [truncated by receiver: exceeded {MAX_MEMORY_CONTENT_LENGTH} byte cap]")
});

/// Actor who performed a memory mutation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryRevisionActor {
    Ai,
    Human,
}

impl MemoryRevisionActor {
    pub const fn as_str(&self) -> &'static str {
        match self {
            Self::Ai => "ai",
            Self::Human => "human",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "ai" => Some(Self::Ai),
            "human" => Some(Self::Human),
            _ => None,
        }
    }
}

impl std::fmt::Display for MemoryRevisionActor {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Operation kind on a memory revision row.
///
/// The closed set lives here as a typed enum so the apply boundary
/// parses once via [`MemoryRevisionOperation::parse`] and downstream
/// callers exhaustive-match on the variants. Without this anchor the
/// set would drift across three parallel declarations — an allowlist
/// in `lorvex-sync::apply::child`, a string column in the
/// `memory_revisions` table, and a SQL CHECK constraint in the
/// schema.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryRevisionOperation {
    Upsert,
    Delete,
    Restore,
}

impl MemoryRevisionOperation {
    pub const fn as_str(&self) -> &'static str {
        match self {
            Self::Upsert => "upsert",
            Self::Delete => "delete",
            Self::Restore => "restore",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "upsert" => Some(Self::Upsert),
            "delete" => Some(Self::Delete),
            "restore" => Some(Self::Restore),
            _ => None,
        }
    }

    /// Closed set, in stable order, for diagnostic / error wording.
    pub const fn all() -> &'static [MemoryRevisionOperation] {
        &[
            MemoryRevisionOperation::Upsert,
            MemoryRevisionOperation::Delete,
            MemoryRevisionOperation::Restore,
        ]
    }
}

impl std::fmt::Display for MemoryRevisionOperation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Ownership classification for a memory key. The enum gives every
/// call site exhaustive matching so the compiler refuses to forget a
/// new variant. A bare [`is_human_owned_memory_key`] predicate alone
/// would leave the writable side implicit ("anything that isn't
/// `notes_for_ai`"); adding a future human-reserved key would then
/// require every AI-gated call site to remember to include it, and a
/// missed update would silently widen AI write authority.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryKeyOwnership {
    /// The key is reserved for direct user editing. The AI assistant
    /// must not write to it; only the UI's notes editor and import
    /// flows do.
    HumanOnly,
    /// The key is writable by the AI assistant (and by the human, in
    /// surfaces that allow it). This is the default for all keys not
    /// in the human-reserved set.
    AiWritable,
}

impl MemoryKeyOwnership {
    /// Classify a memory key. The single source of truth for the
    /// human-reserved set; both [`is_human_owned_memory_key`] and
    /// [`is_ai_writable_memory_key`] route through this.
    pub fn classify(key: &str) -> Self {
        if key == MEMORY_KEY_NOTES_FOR_AI {
            Self::HumanOnly
        } else {
            Self::AiWritable
        }
    }
}

/// Check if a memory key is human-owned (reserved for direct user editing).
pub fn is_human_owned_memory_key(key: &str) -> bool {
    matches!(
        MemoryKeyOwnership::classify(key),
        MemoryKeyOwnership::HumanOnly
    )
}

/// Check if a memory key is writable by the AI assistant. Audit
/// #2908-L3: symmetric counterpart to [`is_human_owned_memory_key`].
/// Any new human-reserved key added in the future MUST be reflected
/// in [`MemoryKeyOwnership::classify`]; this predicate then auto-
/// updates and every call site that gates AI writes through it stays
/// correct without having to be edited.
pub fn is_ai_writable_memory_key(key: &str) -> bool {
    matches!(
        MemoryKeyOwnership::classify(key),
        MemoryKeyOwnership::AiWritable
    )
}

#[cfg(test)]
mod tests;
