import { toIpcErrorMessage } from '@/lib/ipc/core.logic';

export function isListNotFoundError(error: unknown): boolean {
  return /not found/i.test(toIpcErrorMessage(error));
}
