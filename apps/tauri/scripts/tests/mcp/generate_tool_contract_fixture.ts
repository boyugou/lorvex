import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

import {
  CONTRACT_FIXTURE_PATH,
  MCP_SERVER_BINARY,
  REPO_ROOT,
  TOOL_CONTRACT_FIXTURE_SCHEMA_VERSION,
  canonicalize,
  sha256Hex,
} from './contracts/shared.ts';

type McpClient = Client;

async function createClient(dbPath: string): Promise<{ client: McpClient; close: () => Promise<void> }> {
  if (!existsSync(MCP_SERVER_BINARY)) {
    throw new Error(`Rust MCP binary not found: ${MCP_SERVER_BINARY}. Run "cargo build --manifest-path mcp-server/Cargo.toml" first.`);
  }

  const transport = new StdioClientTransport({
    command: MCP_SERVER_BINARY,
    args: [],
    cwd: REPO_ROOT,
    env: {
      DB_PATH: dbPath,
      LORVEX_AGENT_NAME: 'contract-fixture-generator',
    },
    stderr: 'pipe',
  });

  const client: McpClient = new Client({
    name: 'mcp-contract-fixture-generator',
    version: '0.1.0',
  });

  await client.connect(transport);
  return {
    client,
    close: async () => {
      await client.close();
    },
  };
}

async function main(): Promise<void> {
  const tempDir = mkdtempSync(join(tmpdir(), 'lorvex-mcp-contract-fixture-'));
  const dbPath = join(tempDir, 'db.sqlite');

  try {
    const { client, close } = await createClient(dbPath);
    try {
      const listToolsResult = await client.listTools();
      const tools = [...listToolsResult.tools].sort((a, b) => a.name.localeCompare(b.name));

      const fixture = {
        schema_version: TOOL_CONTRACT_FIXTURE_SCHEMA_VERSION,
        generated_at: new Date().toISOString(),
        server_entry: 'target/debug/lorvex-mcp-server',
        tool_count: tools.length,
        tools: tools.map((tool) => {
          const canonicalSchema = canonicalize(tool.inputSchema);
          const canonicalSchemaJson = JSON.stringify(canonicalSchema);
          return {
            name: tool.name,
            description_sha256: sha256Hex(tool.description ?? ''),
            schema_sha256: sha256Hex(canonicalSchemaJson),
          };
        }),
      };

      writeFileSync(CONTRACT_FIXTURE_PATH, `${JSON.stringify(fixture, null, 2)}\n`, 'utf8');
      console.log(`[contracts] wrote ${CONTRACT_FIXTURE_PATH}`);
      console.log(`[contracts] tools: ${fixture.tool_count}`);
    } finally {
      await close();
    }
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error('[contracts] failed to generate tool contract fixture:', error);
  process.exit(1);
});
