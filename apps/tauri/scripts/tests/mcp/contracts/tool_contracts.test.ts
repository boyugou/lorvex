import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CONTRACT_FIXTURE_PATH,
  TOOL_CONTRACT_FIXTURE_SCHEMA_VERSION,
  canonicalize,
  createHarness,
  readJsonFixture,
  sha256Hex,
  type ToolContractFixture,
} from './shared.ts';

test('tool contract snapshot matches frozen fixture', async (t) => {
  const harness = await createHarness('tool-contract');
  t.after(async () => {
    await harness.cleanup();
  });

  const expected = readJsonFixture<ToolContractFixture>(CONTRACT_FIXTURE_PATH);
  assert.equal(
    expected.schema_version,
    TOOL_CONTRACT_FIXTURE_SCHEMA_VERSION,
    'Unexpected tool contract fixture schema_version. Update the constant and fixture together when the fixture format changes.',
  );
  const listToolsResult = await harness.client.listTools();
  const currentTools = [...listToolsResult.tools]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((tool) => ({
      name: tool.name,
      description_sha256: sha256Hex(tool.description ?? ''),
      schema_sha256: sha256Hex(JSON.stringify(canonicalize(tool.inputSchema))),
    }));

  assert.deepEqual(
    {
      schema_version: TOOL_CONTRACT_FIXTURE_SCHEMA_VERSION,
      server_entry: 'target/debug/lorvex-mcp-server',
      tool_count: currentTools.length,
      tools: currentTools,
    },
    {
      schema_version: expected.schema_version,
      server_entry: expected.server_entry,
      tool_count: expected.tool_count,
      tools: expected.tools,
    },
    'Tool contract drift detected. If intentional, regenerate fixture via `npm run test:mcp:contracts:update`.',
  );
});
