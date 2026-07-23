import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

const read = (relPath) => fs.readFileSync(path.join(repoRoot, relPath), 'utf8');

test('MCP treats notes_for_ai as human-owned read-only context rather than exposing a write contract stub', () => {
  const workflowSource = read('mcp-server/src/contract/workflow.rs');
  // server_memory.rs has been split into server_memory/{mod,gate,write,delete,history,read,tests}.rs.
  // The "human-owned and cannot be changed through MCP" guard now lives in
  // delete.rs / write.rs / history.rs (the gates that reject MCP writes for
  // notes_for_ai). Read the entire module tree so the contract finds the
  // guard wherever it landed after the split.
  const memorySource = readRustSources('mcp-server/src/memory');
  const featuresSource = read('docs/design/FEATURES.md');
  const skillSource = read('skill/SKILL.md');

  assert.doesNotMatch(
    workflowSource,
    /struct SetNotesForAiArgs/,
    'MCP workflow contract should not retain a dead SetNotesForAiArgs write stub',
  );
  assert.match(
    memorySource,
    /human-owned and cannot be changed through MCP/,
    'MCP memory runtime should explicitly guard notes_for_ai as human-owned',
  );
  assert.match(
    featuresSource,
    /not writable by AI through MCP/,
    'canonical product docs should continue describing notes_for_ai as read-only to MCP',
  );
  assert.doesNotMatch(
    skillSource,
    /\bset_notes_for_ai\b/,
    'skill guidance must not advertise a removed/forbidden notes_for_ai MCP write tool',
  );
  assert.match(
    skillSource,
    /do not write it through MCP/i,
    'skill guidance should tell assistants that notes_for_ai is read-only through MCP',
  );
});
