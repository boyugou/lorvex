import { toUserFacingErrorMessage } from '@/lib/ipc/core.logic';

export function formatChangelogActionErrorMessage(error: unknown, fallback: string): string {
  const detail = toUserFacingErrorMessage(error, fallback);
  return detail === fallback ? fallback : `${fallback}: ${detail}`;
}
