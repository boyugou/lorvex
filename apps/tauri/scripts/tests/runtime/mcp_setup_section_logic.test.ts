import assert from 'node:assert/strict';
import test from 'node:test';

import type { McpServerStatus } from '../../../app/src/lib/ipc';
import {
  buildMcpStatusDiagnostics,
  shouldPromptCliMcpTakeover,
  shouldShowAppMcpSnippets,
} from '../../../app/src/components/settings/assistant/McpSetupSection.logic';

function status(overrides: Partial<McpServerStatus>): McpServerStatus {
  return {
    resolved: true,
    command: '/Applications/Lorvex.app/Contents/Resources/mcp-server/lorvex-mcp-server',
    args: [],
    cwd: null,
    error: null,
    mcp_host_authority: null,
    cli_detected: false,
    ...overrides,
  };
}

test('settings prompts CLI takeover when CLI is installed but App is current MCP authority', () => {
  const appAuthorityWithCli = status({
    mcp_host_authority: 'app',
    cli_detected: true,
  });

  assert.equal(shouldPromptCliMcpTakeover(appAuthorityWithCli), true);
  assert.equal(shouldShowAppMcpSnippets(appAuthorityWithCli), false);
});

test('settings keeps App snippets for app-only MCP and hides them for CLI authority', () => {
  assert.equal(
    shouldShowAppMcpSnippets(status({ mcp_host_authority: 'app', cli_detected: false })),
    true,
  );
  assert.equal(
    shouldShowAppMcpSnippets(status({ mcp_host_authority: 'cli', cli_detected: true })),
    false,
  );
  assert.equal(
    shouldShowAppMcpSnippets(status({ mcp_host_authority: 'cli', cli_detected: false })),
    false,
  );
  assert.equal(
    shouldPromptCliMcpTakeover(status({ mcp_host_authority: 'cli', cli_detected: false })),
    false,
  );
});

test('MCP status diagnostics separate localized summaries from raw backend detail', () => {
  assert.deepEqual(
    buildMcpStatusDiagnostics('ipc timeout from get_mcp_server_status', 'spawn ENOENT'),
    [
      {
        detail: 'ipc timeout from get_mcp_server_status',
        summaryKey: 'settings.mcpStatusLoadFailed',
        tone: 'danger',
      },
      {
        detail: 'spawn ENOENT',
        summaryKey: 'settings.mcpStatusServerError',
        tone: 'warning',
      },
    ],
  );
  assert.deepEqual(buildMcpStatusDiagnostics(null, null), []);
});
