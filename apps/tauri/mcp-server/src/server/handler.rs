//! `impl ServerHandler for LorvexMcpServer` — the rmcp transport
//! adapter.
//!
//! we intentionally do NOT use `#[tool_handler(router =
//! self.tool_router)]` here. The macro expands to a `call_tool`
//! implementation that delegates straight to
//! `self.tool_router.call(tcc)` with no interception point, so there's
//! no way to layer the #2385 watchdog timeout on top. Instead we
//! reproduce the exact bodies the macro would generate for
//! `list_tools` and `get_tool`, and wrap `call_tool` in
//! `run_with_timeout` so a slow handler can never block the stdio
//! transport indefinitely. If you update rmcp and the macro's output
//! changes, re-check `list_tools`/`get_tool` against
//! `rmcp_macros::tool_handler` in the new version.

use rmcp::{
    handler::server::tool::ToolCallContext,
    model::{
        CallToolRequestParams, CallToolResult, Implementation, ListToolsResult,
        PaginatedRequestParams, ServerCapabilities, ServerInfo, Tool,
    },
    service::RequestContext,
    ErrorData, RoleServer, ServerHandler,
};

use super::LorvexMcpServer;
use crate::runtime::tool_timeout::run_with_timeout;

impl ServerHandler for LorvexMcpServer {
    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        // Capture the tool name up-front; `request` is consumed by
        // `ToolCallContext::new`, so the error message built inside
        // `run_with_timeout` would otherwise need a second clone.
        let tool_name = request.name.to_string();
        let tcc = ToolCallContext::new(self, request, context);
        let _guard = self.in_flight.enter();
        run_with_timeout(&tool_name, self.tool_timeout, self.tool_router.call(tcc)).await
    }

    async fn list_tools(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        Ok(ListToolsResult {
            tools: self.tool_router.list_all(),
            meta: None,
            next_cursor: None,
        })
    }

    fn get_tool(&self, name: &str) -> Option<Tool> {
        self.tool_router.get(name).cloned()
    }

    fn get_info(&self) -> ServerInfo {
        let capabilities = ServerCapabilities::builder().enable_tools().build();
        ServerInfo::new(capabilities)
            .with_server_info(Implementation::new("lorvex", env!("CARGO_PKG_VERSION")))
            .with_instructions(
                "Lorvex is an AI-native planning system with a first-class standalone app. \
                You are a high-power MCP operator on the write path — the app is read-focused.\n\n\
                Starting a session: call get_session_context once for bounded context across \
                memory, overview, focus, calendar, and recent AI activity. Skip it for narrow \
                follow-ups. get_setup_status for first-run checks; get_guide for topic help.\n\n\
                Capturing tasks: create_task / batch_create_tasks from the user's description. \
                Leave estimated_minutes blank when you genuinely don't know — don't invent \
                false precision. Use raw_input to preserve the user's original phrasing.\n\n\
                The two-date model (MOST-COMMON MISTAKE): due_date is the external deadline, \
                planned_date is the day you intend to work on the task. When the user says \
                'defer to Friday' or 'do this tomorrow', touch planned_date — NOT due_date. \
                Use defer_task for this; update_task only when the user is changing the actual \
                deadline.\n\n\
                Priority is importance, NOT urgency. A task does not 'become' P1 because it \
                is overdue; its priority reflects how much the outcome matters. Urgency is \
                derived from due/planned dates — let the sort order handle it.\n\n\
                Planning today: propose_daily_schedule → user confirms → save_focus_schedule. \
                set_current_focus REPLACES the focus list; add_to_current_focus APPENDS.\n\n\
                Someday is a first-class state for non-active commitments, not a trash bucket. \
                Prefer cancel_task over permanent_delete_task. Reopen restores reminders too.\n\n\
                Review + learn: get_weekly_review_brief for the retrospective surface. \
                ai_changelog records every write you make — read it to recall your own actions.\n\n\
                When something's missing or awkward, open a GitHub issue with a concrete \
                summary instead of working around it.\n\n\
                Every write logs to ai_changelog automatically — you never need to log manually.",
            )
    }
}
