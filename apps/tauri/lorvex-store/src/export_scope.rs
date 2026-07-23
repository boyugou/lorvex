use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExportCategory {
    Tasks,
    Lists,
    Calendar,
    Habits,
    DailyReviews,
    Memory,
    Preferences,
    Focus,
    Subscriptions,
    Audit,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExportScopeKind {
    Full,
    Scoped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExportDependencyMode {
    Closure,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExportScope {
    pub kind: ExportScopeKind,
    pub categories: Vec<ExportCategory>,
    pub dependency_mode: ExportDependencyMode,
}

impl ExportScope {
    pub const fn full() -> Self {
        Self {
            kind: ExportScopeKind::Full,
            categories: Vec::new(),
            dependency_mode: ExportDependencyMode::Closure,
        }
    }

    pub fn scoped<I>(categories: I) -> Self
    where
        I: IntoIterator<Item = ExportCategory>,
    {
        let categories: BTreeSet<_> = categories.into_iter().collect();
        Self {
            kind: ExportScopeKind::Scoped,
            categories: categories.into_iter().collect(),
            dependency_mode: ExportDependencyMode::Closure,
        }
    }

    pub const fn is_full(&self) -> bool {
        matches!(self.kind, ExportScopeKind::Full)
    }

    pub fn includes(&self, category: ExportCategory) -> bool {
        self.is_full() || self.categories.contains(&category)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportValidationSeverity {
    Error,
    Warning,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportValidationFinding {
    pub severity: ImportValidationSeverity,
    pub code: String,
    pub message: String,
}
