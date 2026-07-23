import type { McpServerStatus } from '@/lib/ipc/settings';
import { QUERY_KEYS } from '../query/queryKeys';

const MCP_SERVER_STATUS_STALE_TIME_MS = 5 * 60 * 1000;
const MCP_SERVER_STATUS_GC_TIME_MS = 30 * 60 * 1000;

type McpServerStatusKey = ReturnType<typeof QUERY_KEYS.mcpServerStatus>;

function mcpServerStatusKey(): McpServerStatusKey {
  return QUERY_KEYS.mcpServerStatus();
}

type GetMcpServerStatusFn = (signal?: AbortSignal) => Promise<McpServerStatus>;

export function createMcpServerStatusQueryOptions(
  supportsMcpHosting: boolean,
  getStatus: GetMcpServerStatusFn,
) {
  return {
    queryKey: mcpServerStatusKey(),
    queryFn: ({ signal }: { signal: AbortSignal }) => getStatus(signal),
    enabled: supportsMcpHosting,
    staleTime: MCP_SERVER_STATUS_STALE_TIME_MS,
    gcTime: MCP_SERVER_STATUS_GC_TIME_MS,
    refetchOnWindowFocus: false as const,
  };
}

export function readMcpServerStatusData(
  status: McpServerStatus | undefined,
): McpServerStatus | null {
  return status ?? null;
}
