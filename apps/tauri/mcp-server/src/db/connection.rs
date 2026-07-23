use anyhow::{Context, Result};
use lorvex_store::migration::apply_migrations;
use lorvex_store::schema::all_migrations;
use rusqlite::Connection;

pub fn open_database_for_path(path: &std::path::Path) -> Result<Connection> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("failed to create db directory: {}", parent.display()))?;
    }

    let conn = Connection::open(path)
        .with_context(|| format!("failed to open sqlite database: {}", path.display()))?;

    apply_pragmas(&conn)?;
    apply_migrations(&conn, &all_migrations()).context("failed to apply schema migrations")?;

    Ok(conn)
}

fn apply_pragmas(conn: &Connection) -> Result<()> {
    // Delegate to lorvex-store's canonical PRAGMA block so the MCP
    // binary and the Tauri app never drift. An MCP-local PRAGMA
    // block that omits auto_vacuum (locking an agent-first install
    // into non-incremental mode forever) or temp_store (spilling
    // temp B-trees to disk on crash) is a known regression hazard.
    lorvex_store::apply_standard_pragmas(conn).context("failed to apply sqlite pragmas")?;
    Ok(())
}
