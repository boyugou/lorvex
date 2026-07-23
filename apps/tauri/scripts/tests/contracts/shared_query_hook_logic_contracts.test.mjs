import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('shared query hooks delegate cache-key and normalization policy to dedicated logic modules', () => {
  const savedQueriesHookSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/hooks/useSavedQueries.ts'),
    'utf8',
  );
  const savedQueriesLogicSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/hooks/useSavedQueries.logic.ts'),
    'utf8',
  );
  const mcpStatusHookSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/hooks/useMcpServerStatus.ts'),
    'utf8',
  );
  const mcpStatusLogicSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/hooks/useMcpServerStatus.logic.ts'),
    'utf8',
  );

  assert.match(savedQueriesLogicSource, /export function savedQueriesKey\(/);
  assert.match(savedQueriesLogicSource, /export function createSavedQueriesListQueryOptions\(/);
  assert.match(savedQueriesLogicSource, /export function invalidateSavedQueries\(/);
  assert.match(savedQueriesHookSource, /createSavedQueriesListQueryOptions/);
  assert.match(savedQueriesHookSource, /invalidateSavedQueries/);

  assert.match(mcpStatusLogicSource, /function mcpServerStatusKey\(/);
  assert.match(mcpStatusLogicSource, /export function createMcpServerStatusQueryOptions\(/);
  assert.match(mcpStatusLogicSource, /export function readMcpServerStatusData\(/);
  assert.match(mcpStatusHookSource, /createMcpServerStatusQueryOptions/);
  assert.match(mcpStatusHookSource, /readMcpServerStatusData/);
  assert.doesNotMatch(mcpStatusLogicSource, /invalidateMcpServerStatus/);
  assert.doesNotMatch(mcpStatusHookSource, /invalidateMcpServerStatus/);
});
