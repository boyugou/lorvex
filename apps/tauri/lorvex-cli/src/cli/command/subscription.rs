//! Calendar subscription dispatch enum. Mirrors the clap parse tree
//! at `cli::args::SubscriptionCmd`.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum SubscriptionCommand {
    List {
        format: OutputFormat,
        /// When `true`, the text renderer emits every column. When
        /// `false`, it truncates to a 4-column "feed_url / name /
        /// status / refreshed_ago" view (#4492 item 5). The flag has
        /// no effect on `--format json` — JSON output always carries
        /// the full row shape.
        verbose: bool,
    },
    Add {
        url: String,
        name: Option<String>,
        color: Option<String>,
        format: OutputFormat,
    },
    Remove {
        id: String,
        format: OutputFormat,
    },
    Toggle {
        id: String,
        format: OutputFormat,
    },
    Refresh {
        id: Option<String>,
        all: bool,
        format: OutputFormat,
    },
}
