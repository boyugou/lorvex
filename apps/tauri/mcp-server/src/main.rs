#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Audit-flagged in round-26 CLI env-var review: prior to this
    // guard, `lorvex-mcp-server --version` or `--help` silently
    // started an MCP session and hung waiting for JSON-RPC on stdin.
    // Add a minimal CLI guard so packaging tools / assistants / CI
    // checks can probe the binary without starting the server.
    // Must NOT print to stdout after any non-guard path runs — that
    // would corrupt the JSON-RPC stream the MCP transport uses.
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.as_slice() {
        [arg] if arg == "--version" || arg == "-V" => {
            println!("lorvex-mcp-server {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        [arg] if arg == "--help" || arg == "-h" => {
            println!(
                "lorvex-mcp-server {version}\n\n\
                 Lorvex MCP runtime — speaks JSON-RPC 2.0 over stdio.\n\n\
                 Usage:\n    \
                 lorvex-mcp-server             Start the MCP server on stdio\n    \
                 lorvex-mcp-server --version   Print version and exit\n    \
                 lorvex-mcp-server --help      Print this help and exit\n\n\
                 Configure your MCP-capable assistant (Claude Desktop, \n\
                 Claude Code, Codex, etc.) to spawn this binary — see\n\
                 docs/setup/ASSISTANT_MCP_SETUP.md in the repo.",
                version = env!("CARGO_PKG_VERSION"),
            );
            return Ok(());
        }
        [] => {}
        _ => {
            eprintln!(
                "lorvex-mcp-server: unexpected arguments. Run `lorvex-mcp-server --help` for usage."
            );
            std::process::exit(2);
        }
    }

    lorvex_mcp_server::run_stdio_server().await
}
