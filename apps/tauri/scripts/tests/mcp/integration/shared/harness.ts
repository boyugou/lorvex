import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import Database from 'better-sqlite3';
import { upsertPreference } from './seeds';

const THIS_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(THIS_DIR, '..', '..', '..', '..', '..');
const MCP_SERVER_BINARY = resolve(
  REPO_ROOT,
  'target',
  'debug',
  process.platform === 'win32' ? 'lorvex-mcp-server.exe' : 'lorvex-mcp-server',
);

export const TEST_AGENT_NAME = 'ci-integration-tests';

type McpClient = Client;

export interface TestHarness {
  client: McpClient;
  dbPath: string;
  stderr: () => string;
  cleanup: () => Promise<void>;
}

export async function createHarness(
  name: string,
  envOverrides: Record<string, string> = {},
): Promise<TestHarness> {
  if (!existsSync(MCP_SERVER_BINARY)) {
    throw new Error(
      `Rust MCP binary not found: ${MCP_SERVER_BINARY}. Run "cargo build --manifest-path mcp-server/Cargo.toml" first.`,
    );
  }

  const tempDir = mkdtempSync(join(tmpdir(), `lorvex-mcp-it-${name}-`));
  const dbPath = join(tempDir, 'db.sqlite');

  const transport = new StdioClientTransport({
    command: MCP_SERVER_BINARY,
    args: [],
    cwd: REPO_ROOT,
    env: {
      DB_PATH: dbPath,
      LORVEX_AGENT_NAME: TEST_AGENT_NAME,
      // pin the server's clock to UTC so the Node-side
      // `daysFromTodayYmd` helper (UTC-anchored) agrees with the
      // server's "today" resolver regardless of the CI runner's local
      // tz. Without this pin, any test seeding a date near midnight
      // could disagree on which calendar day "today" is.
      TZ: 'UTC',
      ...envOverrides,
    },
    stderr: 'pipe',
  });

  let stderrBuffer = '';
  transport.stderr?.on('data', (chunk) => {
    stderrBuffer += chunk.toString();
  });

  const client: McpClient = new Client({
    name: 'mcp-integration-test-client',
    version: '0.1.0',
  });

  try {
    await client.connect(transport);
    await client.listTools();
    // Pin the server's anchored timezone to UTC at the preference
    // layer (#3294). The `TZ=UTC` env var above looks like a complete
    // pin but `today_ymd_for_conn` resolves through
    // `lorvex_store::shared_ops::timezone::active_timezone_name`
    // first (PREF_TIMEZONE) and only falls through to
    // `iana_time_zone::get_timezone()` when the preference is unset
    // — and on Linux `iana_time_zone` reads `/etc/localtime` BEFORE
    // the `TZ` env var, so a host with `/etc/localtime → America/New_York`
    // (every default Pitzer cluster, many default Ubuntu CI runners
    // with a non-UTC region pre-configured) ignored the `TZ=UTC` pin
    // entirely. Pre-fix this produced 6 false-positive integration
    // test failures every time the JS-side `daysFromTodayYmd` (UTC)
    // crossed a midnight boundary that the server's NY-local clock
    // had not yet crossed (or vice versa).
    //
    // We can't seed via `set_preference` because the MCP tool's
    // forbidden-key list (`MCP_FORBIDDEN_PREFERENCE_KEYS` in
    // `mcp-server/src/preferences/preferences/storage.rs`) blocks
    // assistant-driven writes to `timezone`, theme, language, etc.
    // The harness opens the DB directly (the schema is now
    // materialized — `client.connect` + `listTools` round-trip
    // forces the migration runner to commit) and writes the
    // preference. WAL mode tolerates the concurrent open.
    const seedDb = new Database(dbPath);
    try {
      upsertPreference(seedDb, 'timezone', 'UTC');
    } finally {
      seedDb.close();
    }
  } catch (error) {
    await client.close().catch(() => undefined);
    rmSync(tempDir, { recursive: true, force: true });
    throw new Error(`Failed to initialize MCP test harness: ${String(error)}\n${stderrBuffer}`);
  }

  return {
    client,
    dbPath,
    stderr: () => stderrBuffer,
    cleanup: async () => {
      await client.close();
      rmSync(tempDir, { recursive: true, force: true });
    },
  };
}

/**
 * Create an additional MCP client connected to an existing DB path.
 * Used for concurrent-write testing where multiple server processes
 * share the same SQLite database (WAL mode).
 */
export async function createSecondaryClient(
  dbPath: string,
  agentName = 'ci-integration-secondary',
): Promise<{ client: McpClient; cleanup: () => Promise<void> }> {
  if (!existsSync(MCP_SERVER_BINARY)) {
    throw new Error(`Rust MCP binary not found: ${MCP_SERVER_BINARY}`);
  }

  const transport = new StdioClientTransport({
    command: MCP_SERVER_BINARY,
    args: [],
    cwd: resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..'),
    env: {
      DB_PATH: dbPath,
      LORVEX_AGENT_NAME: agentName,
    },
    stderr: 'pipe',
  });

  const client: McpClient = new Client({
    name: 'mcp-integration-secondary-client',
    version: '0.1.0',
  });

  await client.connect(transport);
  await client.listTools();

  return {
    client,
    cleanup: async () => {
      await client.close();
    },
  };
}
