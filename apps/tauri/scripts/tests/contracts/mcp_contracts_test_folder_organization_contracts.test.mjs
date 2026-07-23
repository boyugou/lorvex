import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('MCP contract tests are organized as a barrel plus focused modules', () => {
  const rootPath = path.join(repoRoot, 'scripts/tests/mcp/contracts.test.ts');
  const sharedPath = path.join(repoRoot, 'scripts/tests/mcp/contracts/shared.ts');
  const toolContractsPath = path.join(repoRoot, 'scripts/tests/mcp/contracts/tool_contracts.test.ts');
  const goldenCasesPath = path.join(repoRoot, 'scripts/tests/mcp/contracts/golden_cases.test.ts');
  const metadataPath = path.join(repoRoot, 'scripts/tests/mcp/contracts/metadata.test.ts');

  const rootSource = fs.readFileSync(rootPath, 'utf8');
  const sharedSource = fs.readFileSync(sharedPath, 'utf8');
  const toolContractsSource = fs.readFileSync(toolContractsPath, 'utf8');
  const goldenCasesSource = fs.readFileSync(goldenCasesPath, 'utf8');
  const metadataSource = fs.readFileSync(metadataPath, 'utf8');

  assert.match(rootSource, /import '\.\/contracts\/tool_contracts\.test\.ts';/);
  assert.match(rootSource, /import '\.\/contracts\/golden_cases\.test\.ts';/);
  assert.match(rootSource, /import '\.\/contracts\/metadata\.test\.ts';/);
  assert.doesNotMatch(rootSource, /async function createHarness\(|function canonicalize\(|test\('/);

  assert.match(sharedSource, /export async function createHarness\(/);
  assert.match(sharedSource, /export function canonicalize\(/);
  assert.match(sharedSource, /export function sha256Hex\(/);
  assert.match(toolContractsSource, /test\('tool contract snapshot matches frozen fixture'/);
  assert.match(goldenCasesSource, /test\('golden behavior cases keep stable output shape for representative tools'/);
  assert.match(metadataSource, /test\('calendar tool metadata documents recurrence format'/);
  assert.match(metadataSource, /test\('control_app_ui metadata documents supported actions and allowlisted argument values'/);
});
