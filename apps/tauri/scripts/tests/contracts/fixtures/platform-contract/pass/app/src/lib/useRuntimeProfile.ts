import { useMemo } from 'react';
import { getRuntimeProfile, type RuntimeProfile } from './platform/platform';

export function useRuntimeProfile(): RuntimeProfile {
  return useMemo(() => getRuntimeProfile(), []);
}
