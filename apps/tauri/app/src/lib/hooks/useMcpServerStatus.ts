import { useQuery } from '@tanstack/react-query';

import { getMcpServerStatus } from '@/lib/ipc/settings';
import type { McpServerStatus } from '@/lib/ipc/settings';
import { useRuntimeProfile } from '../useRuntimeProfile';
import {
  createMcpServerStatusQueryOptions,
  readMcpServerStatusData,
} from './useMcpServerStatus.logic';

export function useMcpServerStatus(): McpServerStatus | null {
  const { supportsMcpHosting } = useRuntimeProfile();
  const { data } = useQuery(
    createMcpServerStatusQueryOptions(supportsMcpHosting, getMcpServerStatus),
  );
  return readMcpServerStatusData(data);
}
