#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(message) {
  console.error(`[mcp_tools] ERROR: ${message}`);
  process.exit(1);
}

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const repoRoot = path.resolve(scriptDir, '..', '..');
const outputPath = path.join(repoRoot, 'docs', 'design', 'MCP_TOOLS.md');
const mcpSrcDir = path.join(repoRoot, 'mcp-server', 'src');
const verifyOnly = process.argv.includes('--verify');

if (!fs.existsSync(mcpSrcDir)) {
  fail(`MCP server source directory not found: ${mcpSrcDir}`);
}

// ── Discover all files containing #[tool_router(...)] ───────────────
// Primary pattern: every .rs file under mcp-server/src that uses the
// #[tool_router()] macro. Some domains use a single `<domain>/router.rs`,
// while workflow splits its router across sibling files such as
// `workflow/router/focus.rs` and `workflow/router/memory.rs`. The pre-fix
// scan only walked module roots and silently dropped tools defined in
// sibling files, miscounting the inventory and erasing whole domains from the
// rendered doc. We now recurse through the source tree and group every macro
// hit under the parent directory's domain label.

// Issue #3370 finished the flat-tree consolidation: routers now
// uniformly live at `<domain>/router.rs`, with the workflow router
// further split into per-topic siblings under `workflow/router/`.
// There are no longer any top-level `<domain>_router.rs` files.
// The walker recurses through every directory under `mcpSrcDir` and
// collects each `.rs` file with both a display path (relative to
// `mcpSrcDir`) and a domain key derived from the file's location.

// Directories that never contain tool routers and are skipped to keep
// the walker fast and the candidate list focused.
const SKIP_DIRS = new Set(['db', 'error', 'shutdown', 'server']);

function walkRsFiles(dir, relPrefix = '') {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const abs = path.join(dir, entry.name);
    const rel = relPrefix ? `${relPrefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      if (relPrefix === '' && SKIP_DIRS.has(entry.name)) continue;
      out.push(...walkRsFiles(abs, rel));
    } else if (entry.isFile() && entry.name.endsWith('.rs')) {
      out.push({ displayPath: rel, fullPath: abs });
    }
  }
  return out;
}

const allRsFiles = walkRsFiles(mcpSrcDir);

// Domain key strategy: tools are grouped by domain so per-topic
// sibling files (e.g. `workflow/router/focus.rs` + `…/memory.rs`) all
// roll up under one heading instead of fragmenting one-section-per-file.
//
// Post-#3370 every router lives at `<dir>/router.rs` (or under
// `workflow/router/<topic>.rs`), so the parent directory path is
// always the natural domain key — there are no top-level router files
// to special-case.
function deriveDomainKey(displayPath) {
  const parts = displayPath.split('/');
  return parts.slice(0, -1).join('/');
}

const candidates = allRsFiles
  .map(({ displayPath, fullPath }) => ({
    displayPath,
    fullPath,
    domainKey: deriveDomainKey(displayPath),
  }))
  .sort((a, b) => a.displayPath.localeCompare(b.displayPath));

const routerFiles = candidates.filter(({ fullPath }) => {
  const content = fs.readFileSync(fullPath, 'utf8');
  // `tool_router\s*\(` catches the `#[tool_router(...)]` proc-macro
  // attribute. `mcp_tools!` is the declarative wrapper that expands
  // into the same proc-macro at compile time but doesn't carry the
  // literal `tool_router(` token in source — match it explicitly so
  // workflow submodules ported to the macro still show up.
  return /tool_router\s*\(/.test(content) || /\bmcp_tools!\s*\{/.test(content);
});

if (routerFiles.length === 0) {
  fail(`No tool router files found in: ${mcpSrcDir}`);
}

// ── Domain label from filename ──────────────────────────────────────

function domainLabel(domainKey) {
  // calendar               → Calendar
  // tasks                  → Tasks
  // workflow/router        → Workflow
  // workflow/import_export → Import Export
  //
  // Strategy: take the last path segment as the semantic domain. For
  // the per-topic split under `workflow/router/`, the last segment is
  // literally `router`, so prefer the second-to-last (`workflow`).
  const segments = domainKey.split('/');
  const last = segments[segments.length - 1];
  const stem =
    last === 'router' && segments.length > 1
      ? segments[segments.length - 2]
      : last;
  return stem
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

// ── Extract #[tool(name = "...", description = "...")] annotations ──

// Handles both single-line and multi-line #[tool(...)] attributes.
// Also handles tools where description lives in a #[doc = ...] macro
// and only #[tool(name = "...")] is present on the attribute.
function extractTools(source) {
  const tools = [];

  // Find each `#[tool(` start and then track paren balance to find the matching `)`.
  // This correctly handles descriptions with parentheses like "(open/someday)".
  // Match both bare `#[tool(...)]` and the absolute-path form
  // `#[::rmcp::tool(...)]` that the `mcp_tools!` macro's `raw { ... }`
  // blocks emit so the macro doesn't have to rely on `tool` being in
  // the importing module's prelude.
  const toolStartRe = /#\s*\[\s*(?:::\s*)?(?:[A-Za-z_][A-Za-z0-9_]*\s*::\s*)*tool\s*\(/g;
  let startMatch;
  while ((startMatch = toolStartRe.exec(source)) !== null) {
    const openPos = startMatch.index + startMatch[0].length;
    let depth = 1;
    let inString = false;
    let escaped = false;
    let i = openPos;
    while (i < source.length && depth > 0) {
      const ch = source[i];
      if (escaped) {
        escaped = false;
      } else if (ch === '\\' && inString) {
        escaped = true;
      } else if (ch === '"') {
        inString = !inString;
      } else if (!inString) {
        if (ch === '(') depth++;
        else if (ch === ')') depth--;
      }
      if (depth > 0) i++;
    }
    const inner = source.slice(openPos, i);

    // Extract description (may span multiple lines)
    const descMatch = inner.match(/description\s*=\s*"((?:[^"\\]|\\.)*)"/s);
    const description = descMatch
      ? descMatch[1].replace(/\\"/g, '"').replace(/\n\s*/g, ' ').trim()
      : null;

    // Extract name. When `name = "..."` is present, use it. When it's
    // omitted (the `mcp_tools!` macro relies on rmcp's fn-name fallback),
    // recover the name from the `pub(crate) fn <name>(` directly after the
    // attribute. Falling back to the fn name keeps the doc generator in
    // sync with the runtime tool registration.
    const nameMatch = inner.match(/name\s*=\s*"([^"]+)"/);
    let name;
    if (nameMatch) {
      name = nameMatch[1];
    } else {
      // Look forward from the closing `)]` of `#[tool(...)]` for the next
      // `fn <ident>(`. Allow `pub`, `pub(crate)`, `async`, and whitespace
      // between the attribute and the fn keyword.
      const after = source.slice(i + 1);
      // After `)` comes `]` closing the attribute, then optional further
      // `#[...]` attributes, then the fn declaration. Strip the `]` and
      // any intervening whitespace/attributes before matching.
      const fnMatch = after.match(/^\s*\]\s*(?:#\s*\[[^\]]*\]\s*)*(?:pub(?:\s*\([^)]*\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/);
      if (!fnMatch) continue;
      name = fnMatch[1];
    }

    if (description) {
      tools.push({ name, description });
    } else {
      // Strategy 2: description from #[doc = macro_name!()] above #[tool(name = "...")]
      // Look backwards from the match position to find #[doc = ...]
      const beforeBlock = source.slice(0, startMatch.index);
      const docMacroMatch = beforeBlock.match(
        /#\s*\[\s*doc\s*=\s*(\w+)\s*!\s*\(\s*\)\s*\]\s*$/,
      );
      if (docMacroMatch) {
        const macroName = docMacroMatch[1];
        tools.push({
          name,
          description: `(description via ${macroName} macro)`,
        });
      } else {
        tools.push({ name, description: '(no description extracted)' });
      }
    }
  }

  // Also walk mcp_tools! { ... } macro entries: short-form sugar for
  // simple wrappers that doesn't carry an explicit `#[tool]` attribute
  // in the source. Each entry is `<form> <name>(...) -> <handler>; "desc";`
  // where `<form>` is one of `write|write_ref|read|read_ref` (with args)
  // or `read_noargs <name> -> <handler>; "desc";` (no args). `raw { ... }`
  // blocks contain literal `#[tool] fn`s and have already been picked up
  // by the loop above.
  const formRe =
    /\b(write|write_ref|read|read_ref)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?:->\s*[A-Za-z0-9_:]+\s*)?;\s*"((?:[^"\\]|\\.)*)"\s*;/gs;
  let m;
  while ((m = formRe.exec(source)) !== null) {
    const name = m[2];
    const description = m[3].replace(/\\"/g, '"').replace(/\n\s*/g, ' ').trim();
    tools.push({ name, description });
  }
  const noArgsRe =
    /\bread_noargs\s+([A-Za-z_][A-Za-z0-9_]*)\s*->\s*[A-Za-z0-9_:]+\s*;\s*"((?:[^"\\]|\\.)*)"\s*;/gs;
  while ((m = noArgsRe.exec(source)) !== null) {
    const name = m[1];
    const description = m[2].replace(/\\"/g, '"').replace(/\n\s*/g, ' ').trim();
    tools.push({ name, description });
  }

  return tools;
}

// ── Collect tools from all routers ──────────────────────────────────
//
// Group files by `domainKey` so sibling router files inside a domain
// subtree aggregate under a single domain entry instead of rendering one
// section per file. Each domain's `sources` list captures the contributing
// displayPaths for the rendered "Source:" attribution; standalone
// router files contribute exactly one source.

const domainsByKey = new Map();
let totalToolCount = 0;

for (const { displayPath, fullPath, domainKey } of routerFiles) {
  const source = fs.readFileSync(fullPath, 'utf8');
  const tools = extractTools(source);

  if (tools.length === 0) continue;

  totalToolCount += tools.length;

  const existing = domainsByKey.get(domainKey);
  if (existing) {
    existing.tools.push(...tools);
    existing.sources.push(displayPath);
  } else {
    domainsByKey.set(domainKey, {
      label: domainLabel(domainKey),
      sources: [displayPath],
      tools: [...tools],
    });
  }
}

const domains = [...domainsByKey.values()].sort((a, b) =>
  a.label.localeCompare(b.label),
);
for (const domain of domains) {
  domain.tools.sort((a, b) => a.name.localeCompare(b.name));
  domain.sources.sort((a, b) => a.localeCompare(b));
}

if (totalToolCount === 0) {
  fail('No MCP tool annotations found in any router source file');
}

// ── Render markdown ─────────────────────────────────────────────────

function renderMarkdown() {
  const lines = [];

  lines.push('# MCP Tools Reference');
  lines.push('');
  lines.push(
    '> **Generated file** — do not edit manually. Regenerate with `npm run docs:mcp-tools`.',
  );
  lines.push('');
  lines.push(`**Total tools: ${totalToolCount}** across ${domains.length} domains.`);
  lines.push('');

  lines.push('## Write Retry and Idempotency');
  lines.push('');
  lines.push(
    'Retryable write tools expose an optional `idempotency_key`. Generate a fresh opaque key for each intended write, and reuse that key only when retrying the exact same tool payload after a transient transport or session failure. Successful write responses are cached in `mcp_idempotency` for ~24h by `(tool_name, idempotency_key)` and a matching retry replays the cached response byte-for-byte. Reusing a key with a changed payload is rejected through `request_checksum` mismatch detection instead of replaying stale data.',
  );
  lines.push('');

  // Table of contents
  lines.push('## Domains');
  lines.push('');
  for (const domain of domains) {
    const anchor = domain.label.toLowerCase().replace(/ /g, '-');
    lines.push(
      `- [${domain.label}](#${anchor}) (${domain.tools.length} tools)`,
    );
  }
  lines.push('');

  // Per-domain tables
  for (const domain of domains) {
    lines.push(`## ${domain.label}`);
    lines.push('');
    if (domain.sources.length === 1) {
      lines.push(`Source: \`mcp-server/src/${domain.sources[0]}\``);
    } else {
      const sourceList = domain.sources
        .map((s) => `\`mcp-server/src/${s}\``)
        .join(', ');
      lines.push(`Sources: ${sourceList}`);
    }
    lines.push('');
    lines.push('| Tool Name | Description |');
    lines.push('|-----------|-------------|');
    for (const tool of domain.tools) {
      // Escape pipe characters in description for markdown table safety
      const safeDesc = tool.description.replace(/\|/g, '\\|');
      lines.push(`| \`${tool.name}\` | ${safeDesc} |`);
    }
    lines.push('');
  }

  while (lines.at(-1) === '') {
    lines.pop();
  }
  return `${lines.join('\n')}\n`;
}

const content = renderMarkdown();

// ── Verify or write ─────────────────────────────────────────────────

if (verifyOnly) {
  if (!fs.existsSync(outputPath)) {
    fail(
      `MCP tools file missing: docs/design/MCP_TOOLS.md. Run: npm run docs:mcp-tools`,
    );
  }
  const existing = fs.readFileSync(outputPath, 'utf8');
  if (existing !== content) {
    fail(
      `Stale MCP tools file: docs/design/MCP_TOOLS.md. Run: npm run docs:mcp-tools`,
    );
  }
  console.log('[mcp_tools] OK: docs/design/MCP_TOOLS.md is up to date.');
  process.exit(0);
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, content, 'utf8');

console.log('[mcp_tools] Wrote docs/design/MCP_TOOLS.md');
console.log(`[mcp_tools] Total tools: ${totalToolCount} across ${domains.length} domains`);
for (const domain of domains) {
  console.log(`[mcp_tools]   ${domain.label}: ${domain.tools.length} tools`);
}
