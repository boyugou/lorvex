import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

import { seedScaleDataset } from './dataset';
import { evaluateMetadata } from './metadata';
import type { DatasetBenchmarkResult, ToolBenchmarkResult, ToolCase } from './types';

const THIS_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(THIS_DIR, '..', '..', '..', '..');
const RUST_BINARY = resolve(
  REPO_ROOT,
  'target',
  'debug',
  process.platform === 'win32' ? 'lorvex-mcp-server.exe' : 'lorvex-mcp-server',
);

type McpClient = Client;

interface Harness {
  client: McpClient;
  cleanup: () => Promise<void>;
}

function getFirstText(result: unknown): string {
  const payload = result as { content?: Array<{ type?: string; text?: string }> };
  const part = payload.content?.find((p) => p.type === 'text' && typeof p.text === 'string');
  assert.ok(part, 'Expected MCP response text content');
  return part.text!;
}

async function createHarness(dbPath: string): Promise<Harness> {
  if (!existsSync(RUST_BINARY)) {
    throw new Error(`Rust MCP binary not found: ${RUST_BINARY}. Run "cargo build --manifest-path mcp-server/Cargo.toml" first.`);
  }

  const transport = new StdioClientTransport({
    command: RUST_BINARY,
    args: [],
    cwd: REPO_ROOT,
    env: {
      DB_PATH: dbPath,
      LORVEX_AGENT_NAME: 'scale-benchmark-rust',
    },
    stderr: 'pipe',
  });

  let stderrBuffer = '';
  transport.stderr?.on('data', (chunk) => {
    stderrBuffer += chunk.toString();
  });

  const client: McpClient = new Client({
    name: 'scale-benchmark-rust',
    version: '0.1.0',
  });

  try {
    await client.connect(transport);
    await client.listTools();
  } catch (error) {
    await client.close().catch(() => undefined);
    throw new Error(`Failed to initialize Rust MCP harness: ${String(error)}\n${stderrBuffer}`);
  }

  return {
    client,
    cleanup: async () => {
      await client.close();
    },
  };
}

async function runSingleBenchmark(datasetSize: number): Promise<DatasetBenchmarkResult> {
  const tempDir = mkdtempSync(join(tmpdir(), `lorvex-scale-benchmark-rust-${datasetSize}-`));
  const dbPath = join(tempDir, 'db.sqlite');
  const listId = `list-scale-${datasetSize}`;
  try {
    const initHarness = await createHarness(dbPath);
    await initHarness.cleanup();

    seedScaleDataset(dbPath, datasetSize, listId);

    const harness = await createHarness(dbPath);
    try {
      const calls: ToolCase[] = [
        { name: 'list_tasks', args: { list_id: listId, status: 'all' } },
        { name: 'search_tasks', args: { query: 'Scale task', status: 'all' } },
        { name: 'get_deferred_tasks', args: { list_id: listId } },
        { name: 'get_todays_tasks', args: {} },
        { name: 'get_upcoming_tasks', args: { days: 14 } },
        { name: 'get_list', args: { id: listId } },
      ];

      const startedAll = performance.now();
      const tools: ToolBenchmarkResult[] = [];
      for (const c of calls) {
        const started = performance.now();
        const raw = await harness.client.callTool({
          name: c.name,
          arguments: c.args,
        });
        const elapsedMs = Number((performance.now() - started).toFixed(2));
        const text = getFirstText(raw);
        const payloadBytes = Buffer.byteLength(text, 'utf8');
        const payload = JSON.parse(text) as Record<string, unknown>;
        const meta = evaluateMetadata(c.name, payload);

        tools.push({
          tool: c.name,
          elapsed_ms: elapsedMs,
          payload_bytes: payloadBytes,
          metadata_ok: meta.ok,
          metadata_note: meta.note,
          limit: meta.limit,
          returned: meta.returned,
          total_matching: meta.totalMatching,
          truncated: meta.truncated,
        });
      }

      const totalElapsedMs = Number((performance.now() - startedAll).toFixed(2));
      return {
        dataset_size: datasetSize,
        runtime: 'rust',
        tools,
        total_elapsed_ms: totalElapsedMs,
        max_tool_elapsed_ms: Math.max(...tools.map((r) => r.elapsed_ms)),
        max_payload_bytes: Math.max(...tools.map((r) => r.payload_bytes)),
      };
    } finally {
      await harness.cleanup();
    }
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

export async function runBenchmarkSuite(datasets: number[]): Promise<DatasetBenchmarkResult[]> {
  const results: DatasetBenchmarkResult[] = [];
  for (const size of datasets) {
    results.push(await runSingleBenchmark(size));
  }
  return results;
}
