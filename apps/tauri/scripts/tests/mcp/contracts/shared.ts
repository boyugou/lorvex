import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

type McpClient = Client;

interface TestHarness {
  client: McpClient;
  cleanup: () => Promise<void>;
}

export interface ToolResultPayload {
  content?: Array<{ type?: string; text?: string }>;
  isError?: boolean;
}

export interface ToolContractFixture {
  schema_version: number;
  server_entry: string;
  tool_count: number;
  tools: Array<{
    name: string;
    description_sha256: string;
    schema_sha256: string;
  }>;
}

export interface GoldenCase {
  name: string;
  tool: string;
  arguments?: Record<string, unknown>;
  expect: {
    type: 'object' | 'array';
    required_keys?: string[];
    equals?: Record<string, unknown>;
    min_length?: number;
  };
}

const THIS_DIR = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = resolve(THIS_DIR, '..', '..', '..', '..');
export const MCP_SERVER_BINARY = resolve(
  REPO_ROOT,
  'target',
  'debug',
  process.platform === 'win32' ? 'lorvex-mcp-server.exe' : 'lorvex-mcp-server',
);
export const CONTRACT_FIXTURE_PATH = resolve(THIS_DIR, '..', 'fixtures', 'tool-contracts.v1.json');
export const GOLDEN_CASES_PATH = resolve(THIS_DIR, '..', 'fixtures', 'tool-golden-cases.v1.json');
export const TOOL_CONTRACT_FIXTURE_SCHEMA_VERSION = 2;

export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [k: string]: JsonValue };

export function canonicalize(value: unknown): JsonValue {
  if (
    value === null
    || typeof value === 'boolean'
    || typeof value === 'number'
    || typeof value === 'string'
  ) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    const out: Record<string, JsonValue> = {};
    for (const key of Object.keys(obj).sort()) {
      out[key] = canonicalize(obj[key]);
    }
    return out;
  }
  return String(value);
}

export function sha256Hex(input: string): string {
  return createHash('sha256').update(input, 'utf8').digest('hex');
}

export function getFirstTextContent(result: unknown): string {
  const payload = result as ToolResultPayload;
  const firstText = payload.content?.find((part) => part.type === 'text' && typeof part.text === 'string');
  assert.ok(firstText, 'Expected MCP tool result to include a text content block');
  return firstText.text!;
}

export function asToolResultPayload(result: unknown): ToolResultPayload {
  return result as ToolResultPayload;
}

export async function createHarness(name: string): Promise<TestHarness> {
  if (!existsSync(MCP_SERVER_BINARY)) {
    throw new Error(`Rust MCP binary not found: ${MCP_SERVER_BINARY}. Run "cargo build --manifest-path mcp-server/Cargo.toml" first.`);
  }

  const tempDir = mkdtempSync(join(tmpdir(), `lorvex-mcp-contract-${name}-`));
  const dbPath = join(tempDir, 'db.sqlite');

  const transport = new StdioClientTransport({
    command: MCP_SERVER_BINARY,
    args: [],
    cwd: REPO_ROOT,
    env: {
      DB_PATH: dbPath,
      LORVEX_AGENT_NAME: 'contract-tests',
    },
    stderr: 'pipe',
  });

  const client: McpClient = new Client({
    name: 'mcp-contract-test-client',
    version: '0.1.0',
  });

  try {
    await client.connect(transport);
    await client.listTools();
  } catch (error) {
    await client.close().catch(() => undefined);
    rmSync(tempDir, { recursive: true, force: true });
    throw new Error(`Failed to initialize MCP contract test harness: ${String(error)}`);
  }

  return {
    client,
    cleanup: async () => {
      await client.close();
      rmSync(tempDir, { recursive: true, force: true });
    },
  };
}

export function readJsonFixture<T>(path: string): T {
  return JSON.parse(readFileSync(path, 'utf8')) as T;
}
