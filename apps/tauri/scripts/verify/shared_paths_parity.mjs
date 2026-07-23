#!/usr/bin/env node
//
// verify:shared-paths-parity (Audit #2931-M27)
//
// `app/tsconfig.json` declares `compilerOptions.paths` entries that map
// every `@lorvex/shared/<entry>` import to the source `.ts` file under
// `shared/src/`. The same mapping is also expressed declaratively in
// `shared/package.json` under the `exports` field.
//
// If the two definitions drift, `tsc` (which reads tsconfig.paths) and
// the npm workspace resolver (which reads package.json exports) would
// silently disagree about where to find a re-exported module. Tooling
// like `vite`, `vitest`, and `tsx` may pick whichever wins in their
// own resolver, producing "works in tsc, fails at runtime" or vice-
// versa.
//
// This verifier asserts a 1:1 correspondence between every `./<entry>`
// key in `shared/package.json#exports` and the matching
// `@lorvex/shared/<entry>` key in `app/tsconfig.json#compilerOptions.paths`.
// Each tsconfig path target must point at the same `.ts` source the
// package.json export resolves to.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

function fail(message) {
  console.error(`[verify:shared-paths-parity] ${message}`);
  process.exit(1);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const sharedPkgPath = path.join(repoRoot, "shared", "package.json");
const appTsconfigPath = path.join(repoRoot, "app", "tsconfig.json");

if (!fs.existsSync(sharedPkgPath)) {
  fail(`missing ${path.relative(repoRoot, sharedPkgPath)}`);
}
if (!fs.existsSync(appTsconfigPath)) {
  fail(`missing ${path.relative(repoRoot, appTsconfigPath)}`);
}

// Strip JSONC-style line comments so we can `JSON.parse` tsconfig files
// that may legally contain `// ...` comments. We do this conservatively:
// only strip `//` outside of strings.
function parseJsonAllowingComments(source) {
  let out = "";
  let inString = false;
  let escape = false;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (inString) {
      out += ch;
      if (escape) {
        escape = false;
      } else if (ch === "\\") {
        escape = true;
      } else if (ch === "\"") {
        inString = false;
      }
      continue;
    }
    if (ch === "\"") {
      inString = true;
      out += ch;
      continue;
    }
    if (ch === "/" && source[i + 1] === "/") {
      // line comment
      while (i < source.length && source[i] !== "\n") i++;
      out += "\n";
      continue;
    }
    if (ch === "/" && source[i + 1] === "*") {
      // block comment
      i += 2;
      while (i < source.length && !(source[i] === "*" && source[i + 1] === "/")) i++;
      i += 1; // skip past closing /
      continue;
    }
    out += ch;
  }
  return JSON.parse(out);
}

const sharedPkg = JSON.parse(fs.readFileSync(sharedPkgPath, "utf8"));
const tsconfig = parseJsonAllowingComments(
  fs.readFileSync(appTsconfigPath, "utf8"),
);

const exportsMap = sharedPkg.exports;
if (!exportsMap || typeof exportsMap !== "object") {
  fail(
    `shared/package.json#exports is missing or not an object — required for parity check.`,
  );
}

const tsPaths = tsconfig?.compilerOptions?.paths;
if (!tsPaths || typeof tsPaths !== "object") {
  fail(
    `app/tsconfig.json#compilerOptions.paths is missing — required to map @lorvex/shared/* imports to source files.`,
  );
}

// Build the expected tsconfig.paths from the package.json exports.
// Each `./<entry>` -> `./src/<entry>.ts` becomes
// `@lorvex/shared/<entry>` -> `["../shared/src/<entry>.ts"]`.
const errors = [];
const seenTsKeys = new Set();

for (const [exportKey, exportTarget] of Object.entries(exportsMap)) {
  if (typeof exportKey !== "string" || !exportKey.startsWith("./")) {
    errors.push(
      `shared/package.json#exports key must start with "./" (got: ${JSON.stringify(exportKey)})`,
    );
    continue;
  }
  const entryName = exportKey.slice(2); // drop the "./"
  const tsKey = `@lorvex/shared/${entryName}`;
  seenTsKeys.add(tsKey);

  const tsTargets = tsPaths[tsKey];
  if (!tsTargets) {
    errors.push(
      `app/tsconfig.json#compilerOptions.paths is missing entry "${tsKey}" (declared in shared/package.json#exports).`,
    );
    continue;
  }
  if (!Array.isArray(tsTargets) || tsTargets.length !== 1) {
    errors.push(
      `app/tsconfig.json paths["${tsKey}"] must be a single-element array, got ${JSON.stringify(tsTargets)}.`,
    );
    continue;
  }
  const expected = `../shared/${exportTarget.startsWith("./") ? exportTarget.slice(2) : exportTarget}`;
  if (tsTargets[0] !== expected) {
    errors.push(
      `app/tsconfig.json paths["${tsKey}"][0] = ${JSON.stringify(tsTargets[0])} but shared/package.json maps "${exportKey}" -> ${JSON.stringify(exportTarget)} (expected ${JSON.stringify(expected)}).`,
    );
  }
}

// Extra local aliases such as `@/*` belong to the app resolver, not the
// shared package export contract.
for (const tsKey of Object.keys(tsPaths).filter((key) => key.startsWith("@lorvex/shared/"))) {
  if (!seenTsKeys.has(tsKey)) {
    errors.push(
      `app/tsconfig.json#compilerOptions.paths declares "${tsKey}" but shared/package.json#exports has no matching entry.`,
    );
  }
}

if (errors.length > 0) {
  console.error("[verify:shared-paths-parity] drift detected:");
  for (const err of errors) console.error(`  - ${err}`);
  console.error(
    "\nFix by updating either side so that every shared package export\n" +
      "has a matching tsconfig path with the same source file target.",
  );
  process.exit(1);
}

console.log(
  "[verify:shared-paths-parity] app/tsconfig.json paths match shared/package.json exports.",
);
