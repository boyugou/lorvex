import { invokeIpc } from './core';

/**
 * Result of `undo_delete_entity`. The backend returns the canonical
 * re-inserted row JSON; the precise shape depends on the entity kind
 * encoded inside the opaque token. Callers that need typed access to
 * the restored row should narrow at the call site rather than baking
 * union variants into this IPC layer.
 */
export type UndoDeleteEntityResult = unknown;

/**
 * Restore a deleted entity from its snapshot-undo token.
 *
 * Tokens are short-lived (~5s TTL on the backend) and single-use. Past
 * the TTL the backend returns an error — callers should surface this
 * as a "Undo window expired" message rather than retrying.
 */
export const undoDeleteEntity = (
  token: string,
  signal?: AbortSignal,
): Promise<UndoDeleteEntityResult> =>
  invokeIpc<UndoDeleteEntityResult>('undo_delete_entity', { token }, signal);
