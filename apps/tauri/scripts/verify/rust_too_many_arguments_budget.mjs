#!/usr/bin/env node
/**
 * Issue #4028: `#[allow(clippy::too_many_arguments)]` must stay a tracked
 * exception budget, not an unbounded escape hatch.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:rust-too-many-arguments-budget]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);
const TOO_MANY_ARGUMENTS_LINT_PATTERN = /\bclippy\s*::\s*too_many_arguments\b/;
const NESTED_LINT_SUPPRESSION_ATTR_PATTERN =
  /\b(?:allow|expect)\s*\([^)]*\bclippy\s*::\s*too_many_arguments\b[^)]*\)/;

const BUDGET = [
  {
    path: 'lorvex-store/src/repositories/task/write/duplicate.rs',
    symbol: 'duplicate_task',
    category: 'production_api',
    rationale: 'Task duplication still mirrors the full persisted task row shape; keep tracked until the duplicate writer gets an operation params struct.',
  },
  {
    path: 'lorvex-store/src/repositories/current_focus_items.rs',
    symbol: 'sync_upsert_current_focus',
    category: 'production_api',
    rationale: 'Sync apply upsert mirrors the current sync/current-focus row shape and is budgeted for a follow-up typed sync params pass.',
  },
  {
    path: 'lorvex-store/src/repositories/daily_review_ops/mod.rs',
    symbol: 'sync_upsert_daily_review',
    category: 'production_api',
    rationale: 'Daily review sync apply carries many persisted review columns; budgeted until sync upserts share typed row params.',
  },
  {
    path: 'lorvex-store/src/repositories/memory_revision_repo/mod.rs',
    symbol: 'append_revision',
    category: 'production_api',
    rationale: 'Memory revision append maps one revision row into SQL; budgeted for a typed append params cleanup.',
  },
  {
    path: 'lorvex-cli/src/render/habits.rs',
    symbol: 'render_habit_stats',
    category: 'render_helper',
    rationale: 'CLI render helper formats one already-computed stats projection; no mutation or storage API is exposed.',
  },
  {
    path: 'lorvex-cli/src/render/tasks/dependency.rs',
    symbol: 'render_dep_subtree',
    category: 'render_helper',
    rationale: 'CLI ASCII dependency-tree recursive printer threads the output buffer, current node id, prefix, last-child / root flags, the node-by-id and child-list lookup tables, and two visited sets (path-local cycle guard + global already-rendered guard) — each is load-bearing per recursive call.',
  },
  {
    path: 'lorvex-store/src/import/tests/mod.rs',
    symbol: 'write_import_zip_with_manifest',
    category: 'test_support',
    rationale: 'Test fixture helper writes archive sections directly so import tests can vary malformed payloads independently.',
  },
  {
    path: 'lorvex-store/src/import/tests/mod.rs',
    symbol: 'write_import_zip_with_sections',
    category: 'test_support',
    rationale: 'Test fixture helper writes all import archive sections, including intentionally invalid combinations.',
  },
  {
    path: 'lorvex-store/src/repositories/task/read/tests/support.rs',
    symbol: 'insert_task',
    category: 'test_support',
    rationale: 'Task repository tests seed compact task rows with explicit fixture columns.',
  },
  {
    path: 'lorvex-store/src/focus_schedule_blocks/mod.rs',
    symbol: 'sync_upsert_focus_schedule',
    category: 'production_api',
    rationale: 'Focus schedule sync apply mirrors the persisted schedule header shape; budgeted for typed sync params.',
  },
  {
    path: 'lorvex-cli/src/commands/mutate/calendar/effects/tests.rs',
    symbol: 'fields',
    category: 'test_support',
    rationale: 'Calendar mutation tests build explicit event fixture fields, including malformed combinations.',
  },
  {
    path: 'lorvex-cli/src/commands/mutate/habits/mod.rs',
    symbol: 'run_habit_create',
    category: 'ipc_tool_boundary',
    rationale: 'CLI command boundary receives the flat Clap argument shape before delegating into effects.',
  },
  {
    path: 'lorvex-cli/src/commands/mutate/habits/mod.rs',
    symbol: 'run_habit_update',
    category: 'ipc_tool_boundary',
    rationale: 'CLI command boundary receives the flat Clap argument shape before delegating into effects.',
  },
  {
    path: 'app/src-tauri/src/commands/calendar/events/create/mod.rs',
    symbol: 'create_calendar_event',
    category: 'ipc_tool_boundary',
    rationale: 'Tauri IPC command preserves the existing frontend invoke argument shape and immediately normalizes into CreateCalendarEventArgs.',
  },
  {
    path: 'lorvex-store/tests/calendar_timeline/support.rs',
    symbol: 'insert_canonical_event',
    category: 'test_support',
    rationale: 'Calendar timeline integration tests seed direct event rows with explicit fixture fields.',
  },
  {
    path: 'lorvex-store/tests/calendar_timeline/support.rs',
    symbol: 'insert_provider_event',
    category: 'test_support',
    rationale: 'Calendar timeline integration tests seed direct provider event rows with explicit fixture fields.',
  },
  {
    path: 'app/src-tauri/src/commands/habits/queries/writes.rs',
    symbol: 'create_habit',
    category: 'ipc_tool_boundary',
    rationale: 'Tauri IPC command keeps the flat frontend invoke shape and immediately builds CreateHabitParams.',
  },
  {
    path: 'app/src-tauri/src/commands/tests/sync/mod.rs',
    symbol: 'write_sync_envelope_file',
    category: 'test_support',
    rationale: 'Sync tests write intentionally malformed envelope fixtures without typed production constructors.',
  },
  {
    path: 'app/src-tauri/src/commands/tests/sync/mod.rs',
    symbol: 'insert_sync_event_row',
    category: 'test_support',
    rationale: 'Sync tests seed outbox rows directly to exercise parser and collector edge cases.',
  },
  {
    path: 'app/src-tauri/src/commands/tests/task_commands.rs',
    symbol: 'insert_task_for_task_commands_test',
    category: 'test_support',
    rationale: 'Task command tests seed direct task rows with explicit lifecycle fixture columns.',
  },
  {
    path: 'mcp-server/src/server/tests/mod.rs',
    symbol: 'seed_task',
    category: 'test_support',
    rationale: 'MCP server tests seed direct task rows with explicit fixture fields.',
  },
  {
    path: 'app/src-tauri/src/commands/tasks/undo/tokens.rs',
    symbol: 'build_undo_token',
    category: 'production_api',
    rationale: 'Undo-token builder serializes a lifecycle snapshot and related edge sets; budgeted for a typed token params cleanup.',
  },
  {
    path: 'lorvex-workflow/src/task_update/mutation.rs',
    symbol: 'apply_single_update_in_savepoint',
    category: 'production_api',
    rationale: 'Single-row task update orchestrator threads the conn, HLC session, update payload, before snapshot/status, now timestamp, sync effects accumulator, and dep-changed id list; each input is load-bearing for the multi-step savepoint pipeline.',
  },
  {
    path: 'mcp-server/src/runtime/change_tracking/mutation_executor/delegates.rs',
    symbol: 'execute_mcp_mutation_with_undo_tombstone_audit_finalizer',
    category: 'production_api',
    rationale: 'Full undo + tombstone + audit + finalizer executor wires the connection, mutation, MCP tool tag, entity id, undo bundle, tombstone payload map, store-error mapper, and per-call finalize closure as eight independent inputs.',
  },
];

function walkRustFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name))) {
    if (entry.name === '.git' || entry.name === '.worktrees' || entry.name === 'target' || entry.name === 'node_modules') {
      continue;
    }
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkRustFiles(abs));
    } else if (entry.isFile() && entry.name.endsWith('.rs')) {
      files.push(abs);
    }
  }
  return files;
}

function startsRustAttribute(line) {
  return /^\s*#\s*!?\s*\[/.test(line);
}

function readAttributeBlock(lines, startIndex) {
  let text = '';
  let bracketDepth = 0;
  let sawBracket = false;
  for (let i = startIndex; i < lines.length; i += 1) {
    const line = lines[i];
    text += `${text ? '\n' : ''}${line}`;
    for (const char of line) {
      if (char === '[') {
        bracketDepth += 1;
        sawBracket = true;
      } else if (char === ']') {
        bracketDepth -= 1;
      }
    }
    if (sawBracket && bracketDepth <= 0) {
      return {
        text,
        startLine: startIndex + 1,
        endLineIndex: i,
        isInner: /^\s*#\s*!\s*\[/.test(lines[startIndex]),
      };
    }
  }
  throw new Error(`${SCRIPT_TAG} unterminated Rust attribute starting at line ${startIndex + 1}`);
}

function suppressesTooManyArguments(attrText) {
  const trimmed = attrText.trim();
  const attrBody = trimmed
    .replace(/^#\s*!?\s*\[/, '')
    .replace(/\]\s*$/, '')
    .trim();
  const attrName = attrBody.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*\(/)?.[1] ?? '';
  if ((attrName === 'allow' || attrName === 'expect')
    && TOO_MANY_ARGUMENTS_LINT_PATTERN.test(attrBody)) {
    return true;
  }
  return attrName === 'cfg_attr'
    && NESTED_LINT_SUPPRESSION_ATTR_PATTERN.test(attrBody);
}

function extractSymbol(lines, attrEndLineIndex, relPath) {
  for (let i = attrEndLineIndex + 1; i < Math.min(lines.length, attrEndLineIndex + 24); i += 1) {
    const trimmed = lines[i].trim();
    if (trimmed === '' || startsRustAttribute(lines[i]) || trimmed.startsWith('///')) {
      if (startsRustAttribute(lines[i])) {
        i = readAttributeBlock(lines, i).endLineIndex;
      }
      continue;
    }
    const match = trimmed.match(/\bfn\s+([A-Za-z0-9_]+)/);
    if (match) {
      return match[1];
    }
    throw new Error(`${SCRIPT_TAG} expected a function after too_many_arguments allowance in ${relPath}:${attrEndLineIndex + 1}`);
  }
  throw new Error(`${SCRIPT_TAG} could not identify function after allowance in ${relPath}:${attrEndLineIndex + 1}`);
}

export function collectTooManyArgumentsAllowances(repoRoot = REPO_ROOT) {
  const allowances = [];
  for (const abs of walkRustFiles(repoRoot)) {
    const rel = path.relative(repoRoot, abs).split(path.sep).join('/');
    const lines = fs.readFileSync(abs, 'utf8').split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      if (!startsRustAttribute(lines[index])) {
        continue;
      }
      const attr = readAttributeBlock(lines, index);
      index = attr.endLineIndex;
      if (!suppressesTooManyArguments(attr.text)) {
        continue;
      }
      allowances.push({
        path: rel,
        line: attr.startLine,
        symbol: attr.isInner ? '<file>' : extractSymbol(lines, attr.endLineIndex, rel),
      });
    }
  }
  return allowances.sort((left, right) => `${left.path}:${left.symbol}`.localeCompare(`${right.path}:${right.symbol}`));
}

function key(entry) {
  return `${entry.path}::${entry.symbol}`;
}

export function verifyTooManyArgumentsBudget({
  repoRoot = REPO_ROOT,
  budget = BUDGET,
} = {}) {
  const seenBudgetKeys = new Set();
  const duplicateBudgetKeys = [];
  for (const entry of budget) {
    const entryKey = key(entry);
    if (seenBudgetKeys.has(entryKey)) {
      duplicateBudgetKeys.push(entryKey);
    }
    seenBudgetKeys.add(entryKey);
    if (!entry.rationale || entry.rationale.length < 20) {
      throw new Error(`${SCRIPT_TAG} budget entry ${entryKey} needs a concrete rationale`);
    }
  }
  if (duplicateBudgetKeys.length > 0) {
    throw new Error(`${SCRIPT_TAG} duplicate budget entries:\n- ${duplicateBudgetKeys.join('\n- ')}`);
  }

  const allowances = collectTooManyArgumentsAllowances(repoRoot);
  const allowanceKeys = new Set(allowances.map(key));
  const unbudgeted = allowances.filter((entry) => !seenBudgetKeys.has(key(entry)));
  const stale = budget.filter((entry) => !allowanceKeys.has(key(entry)));

  if (unbudgeted.length > 0 || stale.length > 0) {
    const parts = [];
    if (unbudgeted.length > 0) {
      parts.push(`Unbudgeted too_many_arguments allowances:\n- ${unbudgeted.map((entry) => `${entry.path}:${entry.line} ${entry.symbol}`).join('\n- ')}`);
    }
    if (stale.length > 0) {
      parts.push(`Stale budget entries with no matching allowance:\n- ${stale.map((entry) => key(entry)).join('\n- ')}`);
    }
    throw new Error(`${SCRIPT_TAG} ${parts.join('\n\n')}`);
  }

  const countsByCategory = new Map();
  for (const entry of budget) {
    countsByCategory.set(entry.category, (countsByCategory.get(entry.category) ?? 0) + 1);
  }
  const categorySummary = Array.from(countsByCategory)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([category, count]) => `${category}=${count}`)
    .join(', ');
  console.log(`${SCRIPT_TAG} tracked ${allowances.length} allowances (${categorySummary}).`);
}

if (path.resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Rust too_many_arguments budget checks passed.',
    run: verifyTooManyArgumentsBudget,
  });
}
