//! Weekly review tools.
//!
//! Owns the cross-week summary surface: full bounded brief plus a compact
//! snapshot for quick check-in conversations.

use crate::contract::GetWeeklyReviewBriefArgs;
use crate::reviews::weekly;
use tokio_util::sync::CancellationToken;

crate::server::tool_macros::mcp_tools! {
    router = workflow_weekly_review_tool_router;

    raw {
        #[::rmcp::tool(
            description = "Read the full weekly review dataset with bounded sections and truncation metadata. Returns {completed_this_week, stalled_lists, frequently_deferred, overdue_count, someday_items, created_this_week, estimate_summary, section_meta}."
        )]
        pub(crate) async fn get_weekly_review_brief(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<GetWeeklyReviewBriefArgs>,
            ct: CancellationToken,
        ) -> Result<String, String> {
            // #2133: weekly review aggregates several SELECTs with fencing
            // on each result set; the cancellation token is used between
            // blocks so Stop aborts before the next round-trip.
            //
            // #2177: the aggregation is a known runtime-stall hotspot.
            // Dispatch onto the tokio blocking pool so concurrent tool
            // calls and the orphan watchdog keep ticking while the
            // weekly brief is computed.
            self.with_read_conn_typed_async(move |conn| {
                weekly::get_weekly_review_brief(conn, &args, &ct)
            })
            .await
        }
    }

    read_noargs get_weekly_review_snapshot -> weekly::get_weekly_review_snapshot;
        "Compact weekly review: bounded payload with top stalled lists, frequently deferred tasks, and key counts. No customizable limits — designed for quick weekly check-in conversations. Returns {window, counts, top_completed, top_stalled_lists, top_deferred, limits}.";
}
