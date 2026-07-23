import assert from 'node:assert/strict';
import test from 'node:test';

import type { McpServerStatus } from '../../../app/src/lib/ipc';
import {
  createMcpServerStatusQueryOptions,
  readMcpServerStatusData,
} from '../../../app/src/lib/hooks/useMcpServerStatus.logic';

const EXPECTED_MCP_SERVER_STATUS_STALE_TIME_MS = 5 * 60 * 1000;
const EXPECTED_MCP_SERVER_STATUS_GC_TIME_MS = 30 * 60 * 1000;

function status(overrides: Partial<McpServerStatus> = {}): McpServerStatus {
  return {
    resolved: true,
    command: '/usr/local/bin/lorvex-mcp-server',
    args: ['--stdio'],
    cwd: '/repo',
    error: null,
    mcp_host_authority: 'app',
    cli_detected: true,
    ...overrides,
  };
}

test('mcp server status query options encode cache key, timing, and enabled gating', async () => {
  const calls: AbortSignal[] = [];
  const options = createMcpServerStatusQueryOptions(true, async (signal) => {
    calls.push(signal!);
    return status();
  });
  const abortController = new AbortController();

  assert.deepEqual(options.queryKey, ['mcp-server-status']);
  assert.equal(options.enabled, true);
  assert.equal(options.staleTime, EXPECTED_MCP_SERVER_STATUS_STALE_TIME_MS);
  assert.equal(options.gcTime, EXPECTED_MCP_SERVER_STATUS_GC_TIME_MS);
  assert.equal(options.refetchOnWindowFocus, false);
  assert.deepEqual(await options.queryFn({ signal: abortController.signal }), status());
  assert.equal(calls[0], abortController.signal);

  const disabled = createMcpServerStatusQueryOptions(false, async () => status());
  assert.equal(disabled.enabled, false);
});

test('readMcpServerStatusData fails closed to null when the query is empty', () => {
  assert.equal(readMcpServerStatusData(undefined), null);
  assert.deepEqual(readMcpServerStatusData(status({ resolved: false })), status({ resolved: false }));
});
