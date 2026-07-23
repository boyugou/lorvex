#!/usr/bin/env node
//
// verify:readme-cli-subcommands (Audit #2931-L11)
//
// `README.md` shows a Quick Start block that calls the Lorvex CLI with
// concrete subcommand names: `lorvex tasks`, `lorvex graph`,
// `lorvex today`, `lorvex reminder add`, `lorvex trash move`, etc.
// If a subcommand gets renamed in `lorvex-cli/src/cli/args/tree.rs`
// without updating the README, every doc reader following the
// quick-start pastes a command that errors with "no such subcommand".
//
// This verifier extracts every `lorvex <verb> ...` invocation from
// the README's CLI block and asserts that `<verb>` is one of the
// top-level command variants declared by clap-derive in
// `lorvex-cli/src/cli/args/tree.rs`. We check the verb only — argument
// drift is a softer surface and would be caught by the CLI itself
// at first user invocation.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

function fail(message) {
  console.error(`[verify:readme-cli-subcommands] ${message}`);
  process.exit(1);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const readmePath = path.join(repoRoot, "README.md");
const argsPath = path.join(
  repoRoot,
  "lorvex-cli",
  "src",
  "cli",
  "args",
  "tree.rs",
);

if (!fs.existsSync(readmePath)) fail(`missing ${readmePath}`);
if (!fs.existsSync(argsPath)) fail(`missing ${argsPath}`);

// Collect the set of top-level CLI subcommand verbs from
// `lorvex-cli/src/cli/args/tree.rs`. Clap-derive uses `PascalCase`
// enum variants that map to `kebab-case` invocation verbs, with the
// extra rule that single PascalCase words map to lowercase.
const argsSource = fs.readFileSync(argsPath, "utf8");
const enumMatch = argsSource.match(
  /pub(?:\([^)]+\))?\s+enum\s+ClapCommand\s*\{([\s\S]*?)\n\}/,
);
if (!enumMatch) {
  fail("could not locate `pub enum ClapCommand { ... }` in args/tree.rs");
}
const enumBody = enumMatch[1];
// Each top-level command is on its own line as `    Variant ...,`.
// Variants may carry a `#[command(name = "alias", ...)]` attribute on
// any of the lines preceding them; we honor that override and fall
// back to PascalCase→kebab-case for variants without an explicit name.
function pascalToKebab(name) {
  return name.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
}

// Walk the enum body line-by-line. A "variant header line" is one
// indented by exactly 4 spaces and starting with a capital letter
// (clap-derive variant). The block above each header line — between
// the previous variant boundary and this one — holds the
// `#[command(...)]` and `///` attributes we care about. We pick up
// any `name = "..."` from that block and treat it as the explicit
// CLI name; otherwise we fall back to PascalCase→kebab-case.
const enumLines = enumBody.split("\n");
const commandSet = new Set();
const variantSet = new Set();
let attrBuffer = [];
for (const line of enumLines) {
  const variantMatch = line.match(/^ {4}([A-Z][A-Za-z0-9]*)/);
  if (variantMatch) {
    const variant = variantMatch[1];
    variantSet.add(variant);
    const attrText = attrBuffer.join("\n");
    const nameOverride = attrText.match(/name\s*=\s*"([^"]+)"/);
    if (nameOverride) {
      commandSet.add(nameOverride[1]);
    } else {
      commandSet.add(pascalToKebab(variant));
    }
    attrBuffer = [];
    continue;
  }
  attrBuffer.push(line);
}
if (variantSet.size === 0) {
  fail("found 0 ClapCommand variants in args/tree.rs");
}

// Sanity: a few well-known commands must be present so we don't
// false-pass on a regex that happens to capture nothing.
for (const sentinel of ["doctor", "today", "tui"]) {
  if (!commandSet.has(sentinel)) {
    fail(
      `enum extraction is broken: expected sentinel command "${sentinel}" not found. ` +
        `Variants seen: ${Array.from(variantSet).join(", ")}`,
    );
  }
}

const readmeText = fs.readFileSync(readmePath, "utf8");

// Pull every `lorvex <verb>` token from fenced code blocks. We look
// at every occurrence (including in inline code) so a snippet like
// `lorvex changelog` is also covered.
const invocationRegex = /\blorvex\s+([a-z][a-z0-9-]*)/g;
const seen = new Map(); // verb -> first line index
const lines = readmeText.split("\n");
for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  let match;
  while ((match = invocationRegex.exec(line)) !== null) {
    const verb = match[1];
    if (!seen.has(verb)) seen.set(verb, i + 1);
  }
}

// Filter out non-command tokens that legitimately follow `lorvex`.
// `--version` etc would already not match `[a-z][a-z0-9-]*`.
const ALLOWED_NON_COMMANDS = new Set([
  // `lorvex setup --install-mcp-for ...` is `setup`, OK.
  // Add tokens here if a future README usage uses something that is
  // not a top-level command (e.g. `lorvex doc`-style aliases).
]);

const missing = [];
for (const [verb, lineNo] of seen) {
  if (commandSet.has(verb)) continue;
  if (ALLOWED_NON_COMMANDS.has(verb)) continue;
  missing.push({ verb, lineNo });
}

if (missing.length > 0) {
  console.error(
    "[verify:readme-cli-subcommands] README.md references CLI subcommand(s) that\n" +
      "do NOT exist as top-level commands in lorvex-cli/src/cli/args/tree.rs:",
  );
  for (const { verb, lineNo } of missing) {
    console.error(`  - line ${lineNo}: lorvex ${verb}`);
  }
  console.error(
    "\nFix by updating README.md (rename the example) or by adding the missing\n" +
      "command to the CLI. Allowed CLI verbs:\n  " +
      Array.from(commandSet).sort().join(", "),
  );
  process.exit(1);
}

console.log(
  `[verify:readme-cli-subcommands] All ${seen.size} README CLI invocation(s) match an existing top-level command.`,
);
