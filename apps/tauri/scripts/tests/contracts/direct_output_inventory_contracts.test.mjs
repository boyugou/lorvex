import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const SCAN_ROOTS = ['app', 'lorvex-runtime', 'mcp-server'];
const EXCLUDED_PARTS = new Set(['node_modules', 'target', '.history']);
const RUST_OUTPUT_MACRO_PATTERN = /\b(?:eprintln|eprint|println|print|dbg)\s*!\s*[\(\{\[]/g;
const QUALIFIED_STDIO_PATTERN = /\b(?:std::io::|io::)(?:stdout|stderr)\b/g;
const STD_USE_PATTERN = /\buse\s+std(?:::|\s*::\{)[^;]*;/gs;
const UNQUALIFIED_STDIO_CALL_PATTERN = /\b(?:stdout|stderr)\s*\(/g;

const EXPECTED_DIRECT_OUTPUT_LINES = [
  {
    file: 'app/src-tauri/build.rs',
    line: 'println!("cargo::rustc-check-cfg=cfg(desktop)");',
    reason: 'Cargo build-script directive, not application runtime output',
  },
  {
    file: 'app/src-tauri/build.rs',
    line: 'println!("cargo::rerun-if-changed=src/calendar_subscription_sync");',
    reason: 'Cargo build-script generated-handler invalidation directive, not application runtime output',
  },
  {
    file: 'app/src-tauri/build.rs',
    line: 'println!("cargo::rerun-if-changed=src/commands");',
    reason: 'Cargo build-script generated-handler invalidation directive, not application runtime output',
  },
  {
    file: 'app/src-tauri/build.rs',
    line: 'println!("cargo::rerun-if-changed=src/commands.rs");',
    reason: 'Cargo build-script generated-handler invalidation directive, not application runtime output',
  },
  {
    file: 'app/src-tauri/build.rs',
    line: 'println!("cargo::rustc-cfg=desktop");',
    reason: 'Cargo build-script directive, not application runtime output',
  },
  {
    file: 'app/src-tauri/src/commands/calendar/events/update/mod.rs',
    line: 'eprintln!( "calendar_events.dst_ambiguous log insert failed (event already committed): \\ event_id={} err={log_err}", event.id );',
    reason: 'Last-resort diagnostic when the diagnostics error_log insert itself fails after the calendar event row is already committed; surfacing as a validation error here would misclassify the success path. See #4511.',
  },
  {
    file: 'app/src-tauri/src/commands/tests/scale_smoke/metrics.rs',
    line: 'println!( "[scale-smoke] {dataset_label} {}: {}ms rows={}", metric.name, metric.elapsed_ms, metric.rows );',
    reason: 'Rust test-only scale-smoke metric output',
  },
  {
    file: 'lorvex-runtime/build.rs',
    line: 'println!("cargo:rerun-if-changed={}", path.display());',
    reason: 'Cargo build-script directive, not application runtime output',
  },
  {
    file: 'lorvex-runtime/build.rs',
    line: 'println!("cargo:rerun-if-changed=build.rs");',
    reason: 'Cargo build-script directive, not application runtime output',
  },
  {
    file: 'lorvex-runtime/build.rs',
    line: 'println!( "cargo:rustc-env=LORVEX_STORE_SCHEMA_SQL_PATH={}", path.display() );',
    reason: 'Cargo build-script rustc-env directive, not application runtime output',
  },
  {
    file: 'lorvex-runtime/src/test_support/mod.rs',
    line: 'eprintln!( "[lorvex] with_db_path_env_for_test: lock was poisoned by an earlier \\ panicking caller; recovering via into_inner so subsequent tests \\ observe the mutex as available. Investigate the prior panic — \\ poison-recovery is a safety net, not a normal-path event." );',
    reason: 'Rust test-support poison-recovery diagnostic',
  },
  {
    file: 'mcp-server/src/lib.rs',
    line: '.with_writer(std::io::stderr)',
    reason: 'MCP stdio server must reserve stdout for JSON-RPC and send tracing to stderr',
  },
  {
    file: 'mcp-server/src/main.rs',
    line: 'println!("lorvex-mcp-server {}", env!("CARGO_PKG_VERSION"));',
    reason: 'Explicit --version CLI guard output before MCP stdio starts',
  },
  {
    file: 'mcp-server/src/main.rs',
    line: 'println!( "lorvex-mcp-server {version}\\n\\n\\ Lorvex MCP runtime — speaks JSON-RPC 2.0 over stdio.\\n\\n\\ Usage:\\n    \\ lorvex-mcp-server             Start the MCP server on stdio\\n    \\ lorvex-mcp-server --version   Print version and exit\\n    \\ lorvex-mcp-server --help      Print this help and exit\\n\\n\\ Configure your MCP-capable assistant (Claude Desktop, \\n\\ Claude Code, Codex, etc.) to spawn this binary — see\\n\\ docs/setup/ASSISTANT_MCP_SETUP.md in the repo.", version = env!("CARGO_PKG_VERSION"), );',
    reason: 'Explicit --help CLI guard output before MCP stdio starts',
  },
  {
    file: 'mcp-server/src/main.rs',
    line: 'eprintln!( "lorvex-mcp-server: unexpected arguments. Run `lorvex-mcp-server --help` for usage." );',
    reason: 'Explicit unexpected-argument CLI error before MCP stdio starts',
  },
];

function* walkFiles(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (EXCLUDED_PARTS.has(entry.name)) {
      continue;
    }
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walkFiles(fullPath);
    } else if (/\.(rs|mjs|ts|tsx|js|jsx)$/.test(entry.name)) {
      yield fullPath;
    }
  }
}

function compactSnippet(snippet) {
  return snippet
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .join(' ');
}

function lineSnippetAt(source, offset) {
  const start = source.lastIndexOf('\n', offset) + 1;
  const nextLine = source.indexOf('\n', offset);
  const end = nextLine === -1 ? source.length : nextLine;
  return compactSnippet(source.slice(start, end));
}

function statementSnippetAt(source, offset) {
  const statementEnd = source.indexOf(';', offset);
  if (statementEnd === -1) {
    return lineSnippetAt(source, offset);
  }
  return compactSnippet(source.slice(offset, statementEnd + 1));
}

function macroInvocationSnippetAt(source, offset) {
  const macroStart = source.indexOf('!', offset);
  if (macroStart === -1) {
    return lineSnippetAt(source, offset);
  }
  const delimiterMatch = /[\(\{\[]/.exec(source.slice(macroStart));
  if (!delimiterMatch) {
    return lineSnippetAt(source, offset);
  }
  const openDelimiter = macroStart + delimiterMatch.index;
  const delimiterPairs = new Map([
    ['(', ')'],
    ['{', '}'],
    ['[', ']'],
  ]);
  const closingStack = [];

  let depth = 0;
  let inString = false;
  let inChar = false;
  let escaped = false;

  for (let index = openDelimiter; index < source.length; index += 1) {
    const char = source[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }
    if (inChar) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === "'") {
        inChar = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
    } else if (char === "'") {
      inChar = true;
    } else if (delimiterPairs.has(char)) {
      closingStack.push(delimiterPairs.get(char));
      depth += 1;
    } else if (char === closingStack.at(-1)) {
      closingStack.pop();
      depth -= 1;
      if (closingStack.length === 0) {
        let end = index + 1;
        while (end < source.length && /\s/.test(source[end])) {
          end += 1;
        }
        if (source[end] === ';') {
          end += 1;
        }
        return compactSnippet(source.slice(offset, end));
      }
    }
  }

  return lineSnippetAt(source, offset);
}

function stripCommentsAndLiteralsPreservingOffsets(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, (match) =>
    match.replace(/[^\n]/g, ' '),
  ).replace(/\/\/[^\n]*/g, (match) => ' '.repeat(match.length))
    .replace(/r(#+)?"[\s\S]*?"\1/g, (match) => match.replace(/[^\n]/g, ' '))
    .replace(/"(?:\\[\s\S]|[^"\\])*"/g, (match) => match.replace(/[^\n]/g, ' '))
    .replace(/'(?:\\[\s\S]|[^'\\])*'/g, (match) => match.replace(/[^\n]/g, ' '));
}

function directStdioImportStatement(statement) {
  if (!/\bio\b/.test(statement)) {
    return false;
  }
  if (/\b(?:stdout|stderr)\b/.test(statement)) {
    return true;
  }
  if (/\bio\s+as\s+\w+/.test(statement)) {
    return true;
  }
  return /(?:std::io::\{|\bio::)\s*self\s+as\s+\w+/.test(statement);
}

function pushMatch(matches, seen, file, offset, line) {
  const key = `${file}\0${offset}\0${line}`;
  if (line && !seen.has(key)) {
    seen.add(key);
    matches.push({ file, line });
  }
}

function collectDirectOutputLinesFromSource(relPath, source) {
  const matches = [];
  const seen = new Set();
  const searchableSource = stripCommentsAndLiteralsPreservingOffsets(source);

  for (const pattern of [
    RUST_OUTPUT_MACRO_PATTERN,
    STD_USE_PATTERN,
    QUALIFIED_STDIO_PATTERN,
    UNQUALIFIED_STDIO_CALL_PATTERN,
  ]) {
    pattern.lastIndex = 0;
    for (const match of searchableSource.matchAll(pattern)) {
      let line;
      if (pattern === RUST_OUTPUT_MACRO_PATTERN) {
        line = macroInvocationSnippetAt(source, match.index);
      } else if (pattern === STD_USE_PATTERN) {
        if (!directStdioImportStatement(match[0])) {
          continue;
        }
        line = statementSnippetAt(source, match.index);
      } else {
        line = lineSnippetAt(source, match.index);
        if (line.startsWith('use ')) {
          continue;
        }
      }
      pushMatch(matches, seen, relPath, match.index, line);
    }
  }
  return matches;
}

function collectDirectOutputLines() {
  const matches = [];
  for (const root of SCAN_ROOTS) {
    for (const filePath of walkFiles(path.join(repoRoot, root))) {
      const relPath = path.relative(repoRoot, filePath);
      matches.push(...collectDirectOutputLinesFromSource(relPath, fs.readFileSync(filePath, 'utf8')));
    }
  }
  matches.sort((a, b) => `${a.file}\0${a.line}`.localeCompare(`${b.file}\0${b.line}`));
  return matches;
}

test('direct output scanner catches split Rust output macro invocations', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `fn main() {
        eprintln!
        ("hidden diagnostic");
      }`,
    ),
    [
      {
        file: 'fixture.rs',
        line: 'eprintln! ("hidden diagnostic");',
      },
    ],
  );
});

test('direct output scanner catches Rust output macros with alternate delimiters', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `fn main() {
        eprintln! { "hidden diagnostic" };
        dbg![value];
      }`,
    ),
    [
      {
        file: 'fixture.rs',
        line: 'eprintln! { "hidden diagnostic" };',
      },
      {
        file: 'fixture.rs',
        line: 'dbg![value];',
      },
    ],
  );
});

test('direct output scanner catches imported stdout and stderr calls', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `use std::io::{stderr, stdout};

      fn main() {
        let mut err = stderr();
        let out = stdout();
      }`,
    ),
    [
      {
        file: 'fixture.rs',
        line: 'use std::io::{stderr, stdout};',
      },
      {
        file: 'fixture.rs',
        line: 'let mut err = stderr();',
      },
      {
        file: 'fixture.rs',
        line: 'let out = stdout();',
      },
    ],
  );
});

test('direct output scanner catches nested aliased stdio imports', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `use std::{io::stderr as err};

      fn main() {
        let mut output = err();
      }`,
    ),
    [
      {
        file: 'fixture.rs',
        line: 'use std::{io::stderr as err};',
      },
    ],
  );
});

test('direct output scanner catches stdio namespace aliases before output calls', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `use std::io::{self as stdio};

      fn main() {
        let mut output = stdio::stderr();
      }`,
    ),
    [
      {
        file: 'fixture.rs',
        line: 'use std::io::{self as stdio};',
      },
      {
        file: 'fixture.rs',
        line: 'let mut output = stdio::stderr();',
      },
    ],
  );
});

test('direct output scanner catches direct stdio namespace alias imports', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `use std::io as stdio;
      use std::{io as nested_stdio};

      fn main() {
        let mut output = stdio::stderr();
        let out = nested_stdio::stdout();
      }`,
    ),
    [
      {
        file: 'fixture.rs',
        line: 'use std::io as stdio;',
      },
      {
        file: 'fixture.rs',
        line: 'use std::{io as nested_stdio};',
      },
      {
        file: 'fixture.rs',
        line: 'let mut output = stdio::stderr();',
      },
      {
        file: 'fixture.rs',
        line: 'let out = nested_stdio::stdout();',
      },
    ],
  );
});

test('direct output scanner ignores output-looking text inside string literals', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `fn main() {
        let example = "eprintln!(\\"not output\\")";
        let another = "stdout()";
      }`,
    ),
    [],
  );
});

test('direct output scanner ignores output-looking text inside Rust raw string literals', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `fn main() {
        let example = r#"eprintln!("not output")"#;
        let another = r###"stdout()"###;
      }`,
    ),
    [],
  );
});

test('direct output scanner preserves duplicate output occurrences', () => {
  assert.deepEqual(
    collectDirectOutputLinesFromSource(
      'fixture.rs',
      `fn main() {
        println!("same");
        println!("same");
      }`,
    ),
    [
      {
        file: 'fixture.rs',
        line: 'println!("same");',
      },
      {
        file: 'fixture.rs',
        line: 'println!("same");',
      },
    ],
  );
});

test('remaining direct output code sites are intentional and reviewed', () => {
  const actual = collectDirectOutputLines();
  const expected = EXPECTED_DIRECT_OUTPUT_LINES
    .map(({ file, line }) => ({ file, line }))
    .sort((a, b) => `${a.file}\0${a.line}`.localeCompare(`${b.file}\0${b.line}`));

  assert.deepEqual(actual, expected);
  for (const entry of EXPECTED_DIRECT_OUTPUT_LINES) {
    assert.ok(entry.reason.length > 20, `${entry.file}: ${entry.line} must document a reason`);
  }
});

test('architecture docs describe DB locator diagnostics as structured, not stderr fallback', () => {
  const architecture = fs.readFileSync(
    path.join(repoRoot, 'docs/design/ARCHITECTURE.md'),
    'utf8',
  );

  assert.doesNotMatch(
    architecture,
    /locator[\s\S]{0,240}stderr diagnostic/i,
    'DB locator docs must not claim diagnostics fall back to stderr',
  );
  assert.match(architecture, /- \*\*DB locator\.\*\* [^\n]*structured diagnostic/i);
});
