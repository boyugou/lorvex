#!/usr/bin/env node
//
// verify:validation-mirror-parity (#3396)
//
// `lorvex-domain/src/validation/limits.rs` is the source of truth for
// every numeric/string validation cap. `shared/src/validation.ts`
// mirrors those caps so React `<input maxLength>`, form-level
// pre-checks, and other client-side validators line up with what the
// backend will accept. Drift produces two user-visible bugs: a cap
// that is too low silently truncates input at the DOM boundary, and a
// cap that is too high lets the user type past the backend limit and
// see an opaque validation error on submit.
//
// This verifier parses `pub const NAME: TYPE = VALUE;` declarations
// from the Rust source and `export const NAME = VALUE;` declarations
// from the TS source, then asserts every Rust constant has a TS
// counterpart with a matching value. TS is allowed to define extras
// (TS-only validators); Rust-only constants are flagged as drift.
//
// Supported Rust types: `usize`, `i64`, `&str`. Anything else is
// skipped with an explicit log entry (extend the parser when new
// shapes appear in limits.rs).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const rustPath = path.join(repoRoot, "lorvex-domain", "src", "validation", "limits.rs");
const tsPath = path.join(repoRoot, "shared", "src", "validation.ts");

function fail(message) {
  console.error(`[verify:validation-mirror-parity] ${message}`);
  process.exit(1);
}

if (!fs.existsSync(rustPath)) fail(`missing ${path.relative(repoRoot, rustPath)}`);
if (!fs.existsSync(tsPath)) fail(`missing ${path.relative(repoRoot, tsPath)}`);

const rustSrc = fs.readFileSync(rustPath, "utf8");
const tsSrc = fs.readFileSync(tsPath, "utf8");

// ---------------------------------------------------------------------------
// Rust parser
//
// Matches `pub const NAME: TYPE = VALUE;` where TYPE is one of
// `usize`, `i64`, `&str` and VALUE is a literal or a simple arithmetic
// expression of integer literals (`365 * 24 * 3600`, `1_000`, etc.).
// String literals support the simple `"..."` form used in limits.rs
// (no escapes beyond what the current source uses).
// ---------------------------------------------------------------------------
const rustConstRe = /pub\s+const\s+([A-Z][A-Z0-9_]*)\s*:\s*([A-Za-z0-9_&]+)\s*=\s*([^;]+);/g;
const rustConstants = new Map();
const skipped = [];

for (const match of rustSrc.matchAll(rustConstRe)) {
  const [, name, ty, rawValue] = match;
  const value = rawValue.trim();
  if (ty === "usize" || ty === "i64") {
    const numeric = evalRustIntExpr(value);
    if (numeric === null) {
      skipped.push({ name, ty, value, reason: "unparseable integer expression" });
      continue;
    }
    rustConstants.set(name, { kind: "number", value: numeric });
  } else if (ty === "&str") {
    const str = parseRustStringLiteral(value);
    if (str === null) {
      skipped.push({ name, ty, value, reason: "unparseable string literal" });
      continue;
    }
    rustConstants.set(name, { kind: "string", value: str });
  } else {
    skipped.push({ name, ty, value, reason: `unsupported Rust type \`${ty}\`` });
  }
}

function evalRustIntExpr(expr) {
  // Strip integer underscore separators (`1_000` -> `1000`) and then
  // confirm only integer literals + `* + - /` remain. Whitespace OK.
  const stripped = expr.replace(/_/g, "");
  if (!/^[\d\s+\-*/()]+$/.test(stripped)) return null;
  try {
    // eslint-disable-next-line no-new-func
    const result = Function(`"use strict"; return (${stripped});`)();
    return Number.isFinite(result) ? Number(result) : null;
  } catch {
    return null;
  }
}

function parseRustStringLiteral(expr) {
  const m = expr.match(/^"((?:[^"\\]|\\.)*)"$/);
  if (!m) return null;
  // Decode a minimal escape set (\\ \" \n \t) — limits.rs strings are
  // ASCII display tokens so this is sufficient for the current source.
  return m[1].replace(/\\(["\\nt])/g, (_, c) => {
    switch (c) {
      case "n":
        return "\n";
      case "t":
        return "\t";
      default:
        return c;
    }
  });
}

// ---------------------------------------------------------------------------
// TS parser
//
// Matches `export const NAME = VALUE;` for numeric and string-literal
// values. The TS module uses underscore-separated integer literals
// (`50_000`) and quoted strings — both handled below. Arithmetic
// expressions (`365 * 24 * 3600`) are also accepted to match the Rust
// source style.
// ---------------------------------------------------------------------------
const tsConstRe = /export\s+const\s+([A-Z][A-Z0-9_]*)\s*=\s*([^;]+);/g;
const tsConstants = new Map();

for (const match of tsSrc.matchAll(tsConstRe)) {
  const [, name, rawValue] = match;
  const value = rawValue.trim();
  const stringMatch = value.match(/^['"`]((?:[^'"`\\]|\\.)*)['"`]$/);
  if (stringMatch) {
    tsConstants.set(name, { kind: "string", value: stringMatch[1] });
    continue;
  }
  const numeric = evalRustIntExpr(value);
  if (numeric !== null) {
    tsConstants.set(name, { kind: "number", value: numeric });
    continue;
  }
  // Non-trivial TS expressions are allowed (TS-only validators may
  // build derived values); skip silently — Rust drives the contract.
}

// ---------------------------------------------------------------------------
// Compare
// ---------------------------------------------------------------------------
const drift = [];
for (const [name, rustEntry] of rustConstants) {
  const tsEntry = tsConstants.get(name);
  if (!tsEntry) {
    drift.push({ name, reason: "missing in shared/src/validation.ts", rust: rustEntry });
    continue;
  }
  if (tsEntry.kind !== rustEntry.kind) {
    drift.push({
      name,
      reason: `kind mismatch: rust=${rustEntry.kind}, ts=${tsEntry.kind}`,
      rust: rustEntry,
      ts: tsEntry,
    });
    continue;
  }
  if (tsEntry.value !== rustEntry.value) {
    drift.push({
      name,
      reason: "value mismatch",
      rust: rustEntry,
      ts: tsEntry,
    });
  }
}

if (skipped.length > 0) {
  console.warn(
    `[verify:validation-mirror-parity] skipped ${skipped.length} Rust const(s) ` +
      `the parser does not understand (extend the script if these gain TS mirrors):`,
  );
  for (const entry of skipped) {
    console.warn(`  - ${entry.name}: ${entry.reason}`);
  }
}

if (drift.length > 0) {
  console.error(
    `[verify:validation-mirror-parity] drift between ` +
      `lorvex-domain/src/validation/limits.rs and shared/src/validation.ts:`,
  );
  for (const entry of drift) {
    const rustVal = entry.rust ? formatValue(entry.rust) : "(absent)";
    const tsVal = entry.ts ? formatValue(entry.ts) : "(absent)";
    console.error(`  - ${entry.name}: ${entry.reason}`);
    console.error(`      rust=${rustVal}`);
    console.error(`      ts  =${tsVal}`);
  }
  process.exit(1);
}

console.log(
  `[verify:validation-mirror-parity] ok — ${rustConstants.size} Rust const(s) ` +
    `mirrored in shared/src/validation.ts (${tsConstants.size} TS const(s) total).`,
);

function formatValue(entry) {
  return entry.kind === "string" ? JSON.stringify(entry.value) : String(entry.value);
}
