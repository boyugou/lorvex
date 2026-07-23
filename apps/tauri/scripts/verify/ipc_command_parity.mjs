#!/usr/bin/env node
/**
 * IPC command parity — `#[tauri::command]` registrations vs.
 * `invoke('name', …)` call sites.
 *
 * Closes #4406. `build.rs` already covers the forward arrow (every
 * registered command appears in the auto-generated `generate_handler!`
 * list); the inverse arrow — does every registered command have a
 * caller in `ipc.ts`, and does every `invoke('foo')` resolve to a
 * registered handler — was unchecked. A typo on either side ("rename
 * the command but forget to re-point one wrapper") produced a runtime
 * error at the first user click instead of a CI failure.
 *
 * Sources
 *   • Rust:  `app/src-tauri/src/commands/**\/*.rs`. Every `#[tauri::command]`
 *     attribute is followed (after optional doc lines and other
 *     attributes) by a `(pub )?(async )?fn <name>(…)` signature; the
 *     verifier captures the first such identifier.
 *   • TS:    `app/src/lib/ipc/**\/*.ts`. Captures every `invoke(...)`
 *     / `invoke<...>(...)` / `invokeIpc(...)` call whose first
 *     argument is a single- or double-quoted string literal.
 *
 * Outputs
 *   • A clean run prints summary counts and exits 0.
 *   • Ghost endpoints (registered, no caller) and ghost wrappers
 *     (caller, no registration) are listed file:line per occurrence
 *     and exit 1.
 *
 * Heuristics intentionally kept regex-based: a TOML/AST parser would
 * not pay for itself, and the two pattern shapes above are stable
 * project conventions enforced elsewhere (`build.rs` codegen for the
 * Rust side, `ipc.ts` review for the TS side).
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const REPO_ROOT = path.resolve(path.dirname(__filename), '..', '..');
// `#[tauri::command]` registrations live primarily under
// `commands/`, but a handful of legacy / platform-bound subtrees
// (`calendar_subscription_sync/`, native-only modules) keep their
// handlers colocated with the rest of their domain code. Scan the
// entire `src-tauri/src` tree so the verifier doesn't false-positive
// on those wrappers.
const RUST_ROOT = path.join(REPO_ROOT, 'app/src-tauri/src');
const TS_ROOT = path.join(REPO_ROOT, 'app/src/lib/ipc');

/**
 * Recursively yield every file under `dir` whose name matches `extRe`.
 */
function* walk(dir, extRe) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walk(full, extRe);
    } else if (entry.isFile() && extRe.test(entry.name)) {
      yield full;
    }
  }
}

/**
 * Scan Rust sources for `#[tauri::command]` registrations.
 *
 * Returns a Map<commandName, { file, line }[]> — a duplicate
 * registration is itself an error (two functions with the same name
 * cannot both be in `generate_handler![]`), so the map preserves
 * every site for the report.
 */
function scanRustCommands() {
  const registry = new Map();
  for (const file of walk(RUST_ROOT, /\.rs$/)) {
    const text = fs.readFileSync(file, 'utf8');
    const lines = text.split('\n');
    // Track whether the enclosing module is under a `#[cfg(...)]`
      // attribute (e.g. platform-specific stub modules).
    // Brace depth gives us a coarse but reliable scope marker without
    // a full Rust parser. `cfgDepthStack` records the brace depth at
    // which each active cfg-gated scope was opened; popping happens
    // when the depth returns at or below the recorded value.
    let braceDepth = 0;
    const cfgDepthStack = [];
    let pendingCfgForNextBlock = false;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // Bracketed-attribute on its own line — record whether the
      // attribute is a `cfg(…)`. If the same attribute applies to the
      // very next `{ … }` block (a `mod`, an `fn`, an `impl`), defer
      // the cfgDepthStack push until we see the opening brace.
      const attrMatch = line.match(/^\s*#\[(.+)\]\s*$/);
      if (attrMatch && /^\s*cfg\s*\(/.test(attrMatch[1])) {
        pendingCfgForNextBlock = true;
      }
      // Track brace depth. Strings/comments are not handled rigorously
      // because false matches inside them on a *contiguous* line are
      // extremely rare in this codebase, and any drift would surface
      // as a parity failure that's trivial to debug.
      for (const ch of line) {
        if (ch === '{') {
          braceDepth++;
          if (pendingCfgForNextBlock) {
            cfgDepthStack.push(braceDepth);
            pendingCfgForNextBlock = false;
          }
        } else if (ch === '}') {
          braceDepth--;
          while (cfgDepthStack.length > 0 && cfgDepthStack[cfgDepthStack.length - 1] > braceDepth) {
            cfgDepthStack.pop();
          }
        }
      }
      // If a non-cfg, non-`#[tauri::command]` attribute appears
      // before the next block, drop the deferred cfg tag — it was
      // attached to a sibling item.
      if (attrMatch && !/^\s*cfg\s*\(/.test(attrMatch[1]) && pendingCfgForNextBlock
        && !/^\s*tauri::command/.test(attrMatch[1])) {
        pendingCfgForNextBlock = false;
      }
      if (!/^\s*#\[tauri::command(\(.*\))?\]\s*$/.test(line)) continue;
      const inheritedCfg = cfgDepthStack.length > 0;
      // Walk forward past any remaining attributes (`#[…]`) and doc
      // comments (`///` / `//!`) to the `fn` signature.
      let j = i + 1;
      let attributeCfg = false;
      while (j < lines.length) {
        const stripped = lines[j].trim();
        if (stripped.startsWith('#[')) {
          if (/^#\[\s*cfg\s*\(/.test(stripped)) {
            attributeCfg = true;
          }
          j++;
          continue;
        }
        if (
          stripped.startsWith('///') ||
          stripped.startsWith('//!') ||
          stripped.startsWith('//') ||
          stripped === ''
        ) {
          j++;
          continue;
        }
        break;
      }
      if (j >= lines.length) continue;
      const sig = lines[j];
      const m = sig.match(/\b(?:pub\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*[<(]/);
      if (!m) continue;
      const name = m[1];
      const list = registry.get(name) ?? [];
      list.push({
        file: path.relative(REPO_ROOT, file),
        line: i + 1,
        cfgGated: inheritedCfg || attributeCfg,
      });
      registry.set(name, list);
    }
  }
  return registry;
}

/**
 * Scan TS IPC wrappers for `invoke(...)` / `invokeIpc(...)` literal
 * call-sites. Returns Map<commandName, { file, line }[]>.
 */
function scanTsInvokes() {
  const invokers = new Map();
  // Match `invoke('name'`, `invoke<T>('name'`, `invokeIpc('name'`, etc.
  // The leading boundary `[^.A-Za-z0-9_]` (or start-of-line) prevents
  // matches inside identifiers like `myInvoke(...)`. The optional
  // generic-arg block `<…>` tolerates nested generics
  // (`invoke<Array<[…]>>('foo')`) by matching any chars that are not
  // a `(` up to the call-site paren — TS type-arg lists never include
  // a literal `(`, so the paren is a safe stop boundary.
  const RE = /(?:^|[^A-Za-z0-9_.])(invoke[A-Za-z]*)\s*(?:<[^(]*>)?\s*\(\s*(['"])([A-Za-z_][A-Za-z0-9_]*)\2/g;
  for (const file of walk(TS_ROOT, /\.ts$/)) {
    // Exclude *.test.ts files — tests may invoke fictitious commands.
    if (/\.test\.tsx?$/.test(file)) continue;
    const text = fs.readFileSync(file, 'utf8');
    RE.lastIndex = 0;
    let match;
    while ((match = RE.exec(text))) {
      const wrapper = match[1];
      // Only count wrappers whose name is exactly `invoke` /
      // `invokeIpc` — `invokeMutationExecutor` etc. take a structured
      // arg, not a command name string.
      if (wrapper !== 'invoke' && wrapper !== 'invokeIpc') continue;
      const name = match[3];
      const line = text.slice(0, match.index).split('\n').length;
      const list = invokers.get(name) ?? [];
      list.push({ file: path.relative(REPO_ROOT, file), line });
      invokers.set(name, list);
    }
  }
  return invokers;
}

const registered = scanRustCommands();
const invoked = scanTsInvokes();

const errors = [];

// Ghost endpoints: registered handler, no caller.
const ghostEndpoints = [...registered.keys()]
  .filter((name) => !invoked.has(name))
  .sort();
// Ghost wrappers: caller, no registration.
const ghostWrappers = [...invoked.keys()]
  .filter((name) => !registered.has(name))
  .sort();

// Duplicate registrations — same name registered twice. `build.rs`'s
// `generate_handler![]` cannot resolve duplicates, but `cfg`-gated
// platform stubs (`#[cfg(desktop)]` vs `#[cfg(not(desktop))]`) are a
// legitimate pattern that registers the same name twice under
// mutually exclusive build configurations. Treat any pair where at
// least one site is cfg-gated as benign.
const duplicateRegistrations = [...registered.entries()]
  .filter(([, sites]) => sites.length > 1)
  .filter(([, sites]) => sites.every((s) => !s.cfgGated));

if (ghostEndpoints.length > 0) {
  console.error(`ERROR: ${ghostEndpoints.length} ghost endpoint(s) — registered with no caller:`);
  for (const name of ghostEndpoints) {
    for (const { file, line } of registered.get(name)) {
      console.error(`  ${file}:${line}  -> #[tauri::command] '${name}' (no invoke('${name}') match)`);
    }
  }
  errors.push(`${ghostEndpoints.length} ghost endpoint(s)`);
}

if (ghostWrappers.length > 0) {
  console.error(`ERROR: ${ghostWrappers.length} ghost wrapper(s) — caller with no registration:`);
  for (const name of ghostWrappers) {
    for (const { file, line } of invoked.get(name)) {
      console.error(`  ${file}:${line}  -> invoke('${name}') (no #[tauri::command] fn ${name})`);
    }
  }
  errors.push(`${ghostWrappers.length} ghost wrapper(s)`);
}

if (duplicateRegistrations.length > 0) {
  console.error(`ERROR: ${duplicateRegistrations.length} duplicate registration(s):`);
  for (const [name, sites] of duplicateRegistrations) {
    console.error(`  ${name}:`);
    for (const { file, line } of sites) {
      console.error(`    ${file}:${line}`);
    }
  }
  errors.push(`${duplicateRegistrations.length} duplicate registration(s)`);
}

if (errors.length > 0) {
  console.error(`\nipc_command_parity FAILED: ${errors.join(', ')}.`);
  process.exit(1);
}

console.log(
  `OK ipc_command_parity: ${registered.size} #[tauri::command] handlers, ` +
    `${invoked.size} invoke('name') call sites, no drift.`,
);
