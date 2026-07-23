//! Build script for the Tauri backend.
//!
//! Two responsibilities:
//!
//! 1. Configuration: emit the `desktop` cfg alias and run the standard
//!    `tauri_build::build()` step.
//! 2. Codegen (#3315): walk `src/commands/` and
//!    `src/calendar_subscription_sync/`, find every
//!    `#[tauri::command]`-annotated production function, and emit an
//!    `apply_invoke_handlers` function into `OUT_DIR` that expands to
//!    `builder.invoke_handler(tauri::generate_handler![...])` with
//!    module-qualified command paths filled in. `commands.rs`
//!    `include!`s the file, so adding a new command becomes a
//!    2-place edit: the leaf `#[tauri::command]` definition plus an
//!    `ipc.ts` wrapper.
//!
//! The scanner uses a small line-oriented parser instead of `syn`
//! to keep build-time light: every `#[tauri::command]` in this
//! codebase is followed (modulo other attribute lines) by a
//! `pub fn <name>` or `pub async fn <name>` decl, and that is the
//! canonical convention enforced by `commands_handler_audit`.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

const MENU_I18N_KEYS: &[(&str, &str)] = &[
    ("AppMenu", "menu.app"),
    ("FileMenu", "menu.file"),
    ("EditMenu", "menu.edit"),
    ("ViewMenu", "menu.view"),
    ("WindowMenu", "menu.window"),
    ("HelpMenu", "menu.helpMenu"),
    ("Open", "menu.open"),
    ("QuickCapture", "menu.quickCapture"),
    ("Quit", "menu.quit"),
    ("CheckForUpdates", "menu.checkForUpdates"),
    ("Settings", "menu.settings"),
    ("NewTask", "menu.newTask"),
    ("ExportData", "menu.exportData"),
    ("ImportData", "menu.importData"),
    ("Find", "menu.find"),
    ("Today", "menu.today"),
    ("Next7Days", "menu.next7Days"),
    ("AllTasks", "menu.allTasks"),
    ("AiActivity", "menu.aiActivity"),
    ("Calendar", "menu.calendar"),
    ("EisenhowerMatrix", "menu.eisenhowerMatrix"),
    ("KanbanBoard", "menu.kanbanBoard"),
    ("Someday", "menu.someday"),
    ("AiMemory", "menu.aiMemory"),
    ("WeeklyReview", "menu.weeklyReview"),
    ("DailyReview", "menu.dailyReview"),
    ("FocusMode", "menu.focusMode"),
    ("Habits", "menu.habits"),
    ("Dependencies", "menu.dependencies"),
    ("Recurring", "menu.recurring"),
    ("AlwaysOnTop", "menu.alwaysOnTop"),
    ("Help", "menu.help"),
    ("GettingStarted", "menu.gettingStarted"),
    ("AssistantMcpSetup", "menu.assistantMcpSetup"),
    ("KeyboardShortcuts", "menu.keyboardShortcuts"),
    ("ReportIssue", "menu.reportIssue"),
];

fn main() {
    // ---- desktop cfg alias ----------------------------------------------
    println!("cargo::rustc-check-cfg=cfg(desktop)");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS");
    let dominated_by_desktop = matches!(
        target_os.as_deref(),
        Ok("macos") | Ok("windows") | Ok("linux")
    );
    if dominated_by_desktop {
        println!("cargo::rustc-cfg=desktop");
    }

    // ---- handler-inventory codegen --------------------------------------
    emit_handler_inventory(dominated_by_desktop);
    emit_menu_i18n();

    tauri_build::build();
}

/// Walk the command source trees, parse out every
/// `#[tauri::command]` function name, and emit
/// `$OUT_DIR/handler_inventory.rs` with the handler registration
/// function included by `commands.rs`.
fn emit_handler_inventory(dominated_by_desktop: bool) {
    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let src = manifest_dir.join("src");

    // Re-run when any command source changes.
    println!("cargo::rerun-if-changed=src/commands");
    println!("cargo::rerun-if-changed=src/commands.rs");
    println!("cargo::rerun-if-changed=src/calendar_subscription_sync");

    let mut files: Vec<PathBuf> = Vec::new();
    walk_rs(&src.join("commands"), &mut files);
    walk_rs(&src.join("calendar_subscription_sync"), &mut files);
    // `commands.rs` itself contains `mod sticky_stubs { ... }` with
    // mobile fallback `#[tauri::command]` defs; pick those up too.
    if src.join("commands.rs").is_file() {
        files.push(src.join("commands.rs"));
    }

    let mut handlers: BTreeMap<String, CommandHandler> = BTreeMap::new();
    for path in &files {
        let source =
            fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        for name in discover_commands_in_source(&source) {
            let Some(module_path) =
                module_path_for_command_source(&src, path, dominated_by_desktop)
            else {
                continue;
            };
            let handler = CommandHandler {
                path: format!("{module_path}::{name}"),
            };
            if let Some(existing) = handlers.insert(name.clone(), handler.clone()) {
                panic!(
                    "build.rs: duplicate tauri command `{name}` discovered at `{}` and `{}`",
                    existing.path, handler.path
                );
            }
        }
    }

    assert!(
        !handlers.is_empty(),
        "build.rs: no #[tauri::command] functions discovered under src/ \
         — the scanner regressed or the tree was relocated. \
         Refusing to emit an empty handler list."
    );

    let mut body = String::new();
    body.push_str("// AUTO-GENERATED by build.rs (#3315). Do not edit.\n");
    body.push_str("// Source of truth: every `#[tauri::command]` annotated\n");
    body.push_str("// production function under `src/commands/` and\n");
    body.push_str("// `src/calendar_subscription_sync/`.\n");
    body.push_str("//\n");
    body.push_str("// Included inside `commands.rs`, where private command modules\n");
    body.push_str("// are in scope. `lib.rs` only calls this narrow function.\n");
    body.push_str("pub(crate) fn apply_invoke_handlers(\n");
    body.push_str("    builder: ::tauri::Builder<::tauri::Wry>,\n");
    body.push_str(") -> ::tauri::Builder<::tauri::Wry> {\n");
    body.push_str("    builder.invoke_handler(::tauri::generate_handler![\n");
    for handler in handlers.values() {
        body.push_str("        ");
        body.push_str(&handler.path);
        body.push_str(",\n");
    }
    body.push_str("    ])\n");
    body.push_str("}\n");

    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"));
    let out_path = out_dir.join("handler_inventory.rs");
    fs::write(&out_path, body).unwrap_or_else(|e| panic!("write {}: {e}", out_path.display()));
}

#[derive(Debug, Clone)]
struct CommandHandler {
    path: String,
}

fn module_path_for_command_source(
    src: &Path,
    source_path: &Path,
    dominated_by_desktop: bool,
) -> Option<String> {
    let commands_rs = src.join("commands.rs");
    if source_path == commands_rs {
        return (!dominated_by_desktop).then(|| "self::sticky_stubs".to_string());
    }

    let commands_dir = src.join("commands");
    if let Ok(relative) = source_path.strip_prefix(&commands_dir) {
        if !dominated_by_desktop && relative.starts_with("ui/sticky_windows") {
            return None;
        }
        let parts = relative_module_parts(relative);
        return Some(format!("self::{}", parts.join("::")));
    }

    let calendar_subscription_sync_dir = src.join("calendar_subscription_sync");
    if let Ok(relative) = source_path.strip_prefix(calendar_subscription_sync_dir) {
        let module = relative_module_path(relative);
        return if module.is_empty() {
            Some("crate::calendar_subscription_sync".to_string())
        } else {
            Some(format!("crate::calendar_subscription_sync::{module}"))
        };
    }

    panic!(
        "build.rs: cannot derive module path for command source {}",
        source_path.display()
    );
}

fn relative_module_path(path: &Path) -> String {
    relative_module_parts(path).join("::")
}

fn relative_module_parts(path: &Path) -> Vec<String> {
    let mut parts: Vec<String> = path
        .with_extension("")
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect();
    if parts.last().map(String::as_str) == Some("mod") {
        parts.pop();
    }
    parts
}

/// Recursively collect `*.rs` files under `dir`, skipping `tests/`
/// subtrees (test fixtures legitimately declare `#[tauri::command]`
/// on dead-code helpers — same exclusion the
/// `commands_handler_audit` test uses).
fn walk_rs(dir: &Path, out: &mut Vec<PathBuf>) {
    if !dir.is_dir() {
        return;
    }
    for entry in fs::read_dir(dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display())) {
        let entry = entry.expect("dir entry");
        let path = entry.path();
        if path.is_dir() {
            if path.file_name() == Some(std::ffi::OsStr::new("tests")) {
                continue;
            }
            walk_rs(&path, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            out.push(path);
        }
    }
}

/// Pull every production `#[tauri::command]` function name out of
/// `source`. Mirrors the logic in `commands_handler_audit::tests` so
/// codegen and the regression test agree byte-for-byte on what
/// counts as a command.
fn discover_commands_in_source(source: &str) -> Vec<String> {
    let mut out = Vec::new();
    let lines: Vec<&str> = source.lines().collect();
    for idx in 0..lines.len() {
        if lines[idx].trim() != "#[tauri::command]" {
            continue;
        }
        // Walk forward past extra attribute lines / blank lines /
        // doc-comments to the function declaration.
        let mut probe = idx + 1;
        while probe < lines.len() {
            let next = lines[probe].trim();
            if next.is_empty() || next.starts_with("//") || next.starts_with("#[") {
                probe += 1;
                continue;
            }
            break;
        }
        if probe >= lines.len() {
            continue;
        }
        let decl = lines[probe].trim();

        // Skip helpers gated `#[cfg(test)]` on the line immediately
        // before `#[tauri::command]`.
        let mut behind = idx;
        let mut gated_test_only = false;
        while behind > 0 {
            behind -= 1;
            let prev = lines[behind].trim();
            if prev.is_empty() || prev.starts_with("//") {
                continue;
            }
            if prev.starts_with("#[cfg(test)]") {
                gated_test_only = true;
            }
            break;
        }
        if gated_test_only {
            continue;
        }

        if let Some(name) = parse_fn_name(decl) {
            out.push(name);
        }
    }
    out
}

fn parse_fn_name(decl: &str) -> Option<String> {
    let after_pub = decl.strip_prefix("pub ")?;
    if after_pub.starts_with('(') {
        // `pub(crate)` / `pub(super)` — not registerable.
        return None;
    }
    let stripped = after_pub.trim_start_matches("async ");
    let stripped = stripped.strip_prefix("fn ")?;
    let name: String = stripped
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if name.is_empty() {
        None
    } else {
        Some(name)
    }
}

/// Generate the native menu/tray translation lookup from the renderer's
/// canonical JSON catalogs. Only locales with a complete `menu.*`
/// namespace get emitted; partial soft-parity locales fall back to English
/// as a whole so native menus never mix languages.
fn emit_menu_i18n() {
    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let repo_root = manifest_dir
        .parent()
        .and_then(Path::parent)
        .expect("app/src-tauri should have repo root two levels up");
    let locales_dir = repo_root.join("app/src/locales");
    let registry_path = locales_dir.join("registry.ts");
    let strict_parity_path = locales_dir.join("strict-parity.json");

    println!("cargo::rerun-if-changed={}", registry_path.display());
    println!("cargo::rerun-if-changed={}", strict_parity_path.display());
    for entry in fs::read_dir(&locales_dir)
        .unwrap_or_else(|e| panic!("read_dir {}: {e}", locales_dir.display()))
    {
        let entry = entry.expect("locale dir entry");
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) == Some("json") {
            println!("cargo::rerun-if-changed={}", path.display());
        }
    }

    let registry_source = fs::read_to_string(&registry_path)
        .unwrap_or_else(|e| panic!("read {}: {e}", registry_path.display()));
    let locale_codes = parse_locale_registry_codes(&registry_source);
    let locale_code_set: BTreeSet<&str> = locale_codes.iter().map(String::as_str).collect();
    assert!(
        locale_codes.iter().any(|code| code == "en"),
        "locale registry must include English for native menu fallback"
    );
    let strict_parity_codes = parse_strict_parity_locale_codes(&strict_parity_path);
    assert!(
        !strict_parity_codes.is_empty(),
        "strict-parity.json must define at least one native menu parity locale"
    );
    for code in &strict_parity_codes {
        assert!(
            locale_code_set.contains(code.as_str()),
            "strict-parity locale {code}.json must be present in registry.ts"
        );
    }

    let mut complete_locale_tables: Vec<(String, Vec<String>)> = Vec::new();
    for code in &locale_codes {
        let catalog_path = locales_dir.join(format!("{code}.json"));
        let source = fs::read_to_string(&catalog_path)
            .unwrap_or_else(|e| panic!("read {}: {e}", catalog_path.display()));
        let catalog: serde_json::Value = serde_json::from_str(&source)
            .unwrap_or_else(|e| panic!("parse {}: {e}", catalog_path.display()));
        let object = catalog
            .as_object()
            .unwrap_or_else(|| panic!("{} must be a JSON object", catalog_path.display()));
        let mut values = Vec::new();
        let mut complete = true;
        for (_, key) in MENU_I18N_KEYS {
            match object.get(*key).and_then(|value| value.as_str()) {
                Some(value) => values.push(value.to_string()),
                None => {
                    complete = false;
                    break;
                }
            }
        }
        if complete {
            complete_locale_tables.push((code.clone(), values));
        }
    }

    let complete_locale_codes: BTreeSet<&str> = complete_locale_tables
        .iter()
        .map(|(code, _)| code.as_str())
        .collect();
    for code in &strict_parity_codes {
        assert!(
            complete_locale_codes.contains(code.as_str()),
            "{code}.json must define every native menu key because it is listed in strict-parity.json"
        );
    }

    let mut generated = String::new();
    generated.push_str("// AUTO-GENERATED by app/src-tauri/build.rs. Do not edit.\n");
    generated.push_str("// Source: app/src/locales/registry.ts + app/src/locales/*.json\n\n");
    generated.push_str("const KNOWN_LOCALES: &[&str] = &[\n");
    for code in &locale_codes {
        generated.push_str("    \"");
        generated.push_str(&escape_rust_string(code));
        generated.push_str("\",\n");
    }
    generated.push_str("];\n\n");
    generated.push_str("fn lookup(locale: &str, key: MenuKey) -> Option<&'static str> {\n");
    generated.push_str("    Some(match (locale, key) {\n");
    for (code, values) in &complete_locale_tables {
        for ((variant, _), value) in MENU_I18N_KEYS.iter().zip(values) {
            generated.push_str("        (\"");
            generated.push_str(&escape_rust_string(code));
            generated.push_str("\", MenuKey::");
            generated.push_str(variant);
            generated.push_str(") => \"");
            generated.push_str(&escape_rust_string(value));
            generated.push_str("\",\n");
        }
    }
    generated.push_str("        _ => return None,\n");
    generated.push_str("    })\n");
    generated.push_str("}\n");

    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"));
    let out_path = out_dir.join("menu_i18n.generated.rs");
    fs::write(&out_path, generated).unwrap_or_else(|e| panic!("write {}: {e}", out_path.display()));
}

fn parse_locale_registry_codes(source: &str) -> Vec<String> {
    let mut codes = Vec::new();
    for line in source.lines() {
        let Some(start) = line.find("code: '") else {
            continue;
        };
        let rest = &line[start + "code: '".len()..];
        let Some(end) = rest.find('\'') else {
            continue;
        };
        codes.push(rest[..end].to_string());
    }
    codes
}

fn parse_strict_parity_locale_codes(path: &Path) -> Vec<String> {
    let source =
        fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let value: serde_json::Value =
        serde_json::from_str(&source).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()));
    value
        .as_array()
        .unwrap_or_else(|| panic!("{} must be a JSON array", path.display()))
        .iter()
        .map(|item| {
            item.as_str()
                .unwrap_or_else(|| panic!("{} entries must be locale code strings", path.display()))
                .to_string()
        })
        .collect()
}

fn escape_rust_string(raw: &str) -> String {
    raw.chars().flat_map(char::escape_default).collect()
}
