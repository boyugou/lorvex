//! Declarative macros for MCP tool router boilerplate.
//!
//! The rmcp `#[tool_router]` proc-macro requires every tool function to live
//! as an `ImplItem::Fn` inside its target `impl` block — it does NOT re-expand
//! `macro_rules!` invocations sitting at impl-item position. The workaround
//! used here is a tt-muncher accumulator: `mcp_tools!` is invoked at *module*
//! item position, walks the entry list while building up a flat sequence of
//! `#[tool] fn` impl items, and only on the empty-input base case emits the
//! complete `#[tool_router(...)] impl LorvexMcpServer { … }` block. The
//! proc-macro then runs over the fully-expanded fns.
//!
//! Why this exists: ~80% of the wrapper bodies are mechanical
//!   `self.with_conn_typed(|conn| handler(conn, args))` repetition. Collapsing
//!   them removes the 4-place dance for trivial reads/writes; `dispatch_dry_run`
//!   / `idempotency` / fully bespoke tools live verbatim under a `raw { ... }`
//!   escape hatch.
//!
//! Supported entry forms (each followed by a `;`-terminated description
//! literal):
//!
//!   write <name>(<ArgsTy>) -> <handler::path>; "description";
//!     => fn(&self, Parameters(args)) -> Result<String,String> via with_conn_typed.
//!
//!   write_ref <name>(<ArgsTy>) -> <handler::path>; "description";
//!     => same but passes `&args`.
//!
//!   read <name>(<ArgsTy>) -> <handler::path>; "description";
//!     => with_read_conn_typed, args by value.
//!
//!   read_ref <name>(<ArgsTy>) -> <handler::path>; "description";
//!     => with_read_conn_typed, args by reference.
//!
//!   read_noargs <name> -> <handler::path>; "description";
//!     => no `Parameters<...>` argument, calls `with_read_conn_typed(handler)`.
//!
//!   raw { <impl items> }
//!     => splat fully-written `#[tool] fn`s verbatim. Used for dry_run
//!        dispatch, idempotency, async tools, and anything else whose body
//!        isn't a clean fit for the simple variants above. Items inside
//!        `raw { … }` should annotate with `#[::rmcp::tool(...)]` (the
//!        absolute path) since `tool` is not in scope at the call site.
//!
//! The tool name registered with rmcp is derived from the fn name via the
//! `#[tool]` attribute's `Option<String>` fallback (rmcp 1.4: `name:
//! Option<String>` defaults to `fn_ident.to_string()`), so the macro does
//! not need to splat `name = "..."` into the attribute. The doc-generation
//! script (`scripts/generate/mcp_tools.mjs`) was updated to reuse the same
//! fn-name fallback when scanning `#[::rmcp::tool(description = "...")]`
//! attributes that omit `name`.

/// Emit a `#[tool_router] impl LorvexMcpServer { ... }` block populated with
/// thin tool wrappers. See module docs for the entry forms.
macro_rules! mcp_tools {
    (
        router = $router:ident;
        $($body:tt)*
    ) => {
        $crate::server::tool_macros::mcp_tools_munch! {
            @router($router)
            @done()
            @rest($($body)*)
        }
    };
}

/// tt-muncher: pulls one entry off `@rest`, appends its expansion to `@done`,
/// and recurses. When `@rest` is empty, emits the assembled impl block.
macro_rules! mcp_tools_munch {
    // Base case: rest is empty → emit the full impl block.
    (
        @router($router:ident)
        @done($($done:tt)*)
        @rest()
    ) => {
        #[::rmcp::tool_router(router = $router, vis = "pub(crate)")]
        impl crate::server::LorvexMcpServer {
            $($done)*
        }
    };

    // write <name>(<ArgsTy>) -> <handler>; "desc";
    (
        @router($router:ident)
        @done($($done:tt)*)
        @rest(
            write $name:ident ( $args_ty:ty ) -> $($handler:ident)::+ ;
            $desc:literal ;
            $($rest:tt)*
        )
    ) => {
        $crate::server::tool_macros::mcp_tools_munch! {
            @router($router)
            @done(
                $($done)*
                #[::rmcp::tool(description = $desc)]
                pub(crate) fn $name(
                    &self,
                    ::rmcp::handler::server::wrapper::Parameters(args):
                        ::rmcp::handler::server::wrapper::Parameters<$args_ty>,
                ) -> ::std::result::Result<::std::string::String, ::std::string::String> {
                    self.with_conn_typed(|conn| $($handler)::+(conn, args))
                }
            )
            @rest($($rest)*)
        }
    };

    // read <name>(<ArgsTy>) -> <handler>; "desc";
    (
        @router($router:ident)
        @done($($done:tt)*)
        @rest(
            read $name:ident ( $args_ty:ty ) -> $($handler:ident)::+ ;
            $desc:literal ;
            $($rest:tt)*
        )
    ) => {
        $crate::server::tool_macros::mcp_tools_munch! {
            @router($router)
            @done(
                $($done)*
                #[::rmcp::tool(description = $desc)]
                pub(crate) fn $name(
                    &self,
                    ::rmcp::handler::server::wrapper::Parameters(args):
                        ::rmcp::handler::server::wrapper::Parameters<$args_ty>,
                ) -> ::std::result::Result<::std::string::String, ::std::string::String> {
                    self.with_read_conn_typed(|conn| $($handler)::+(conn, args))
                }
            )
            @rest($($rest)*)
        }
    };

    // read_ref <name>(<ArgsTy>) -> <handler>; "desc";
    (
        @router($router:ident)
        @done($($done:tt)*)
        @rest(
            read_ref $name:ident ( $args_ty:ty ) -> $($handler:ident)::+ ;
            $desc:literal ;
            $($rest:tt)*
        )
    ) => {
        $crate::server::tool_macros::mcp_tools_munch! {
            @router($router)
            @done(
                $($done)*
                #[::rmcp::tool(description = $desc)]
                pub(crate) fn $name(
                    &self,
                    ::rmcp::handler::server::wrapper::Parameters(args):
                        ::rmcp::handler::server::wrapper::Parameters<$args_ty>,
                ) -> ::std::result::Result<::std::string::String, ::std::string::String> {
                    self.with_read_conn_typed(|conn| $($handler)::+(conn, &args))
                }
            )
            @rest($($rest)*)
        }
    };

    // read_noargs <name> -> <handler>; "desc";
    (
        @router($router:ident)
        @done($($done:tt)*)
        @rest(
            read_noargs $name:ident -> $($handler:ident)::+ ;
            $desc:literal ;
            $($rest:tt)*
        )
    ) => {
        $crate::server::tool_macros::mcp_tools_munch! {
            @router($router)
            @done(
                $($done)*
                #[::rmcp::tool(description = $desc)]
                pub(crate) fn $name(
                    &self,
                ) -> ::std::result::Result<::std::string::String, ::std::string::String> {
                    self.with_read_conn_typed($($handler)::+)
                }
            )
            @rest($($rest)*)
        }
    };

    // raw { … } — splat fully-written impl items verbatim.
    (
        @router($router:ident)
        @done($($done:tt)*)
        @rest(
            raw { $($items:tt)* }
            $($rest:tt)*
        )
    ) => {
        $crate::server::tool_macros::mcp_tools_munch! {
            @router($router)
            @done(
                $($done)*
                $($items)*
            )
            @rest($($rest)*)
        }
    };
}

pub(crate) use mcp_tools;
pub(crate) use mcp_tools_munch;
