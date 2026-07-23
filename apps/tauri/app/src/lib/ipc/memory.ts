import { invoke, invokeIpc } from './core';

export interface AIMemoryEntry {
  key: string;
  content: string;
  updated_at: string;
  ownership: 'human' | 'ai';
}

export interface MemoryRevisionEntry {
  id: string;
  memory_key: string;
  content: string | null;
  operation: 'upsert' | 'delete' | 'restore';
  source_revision_id: string | null;
  actor: 'ai' | 'human';
  version: string;
  created_at: string;
}

interface MemoryHistoryResult {
  key: string;
  count: number;
  revisions: MemoryRevisionEntry[];
}

interface RestoreMemoryResult {
  restored: boolean;
  key: string;
  from_revision_id: string;
  new_revision_id: string;
}

export const getAiMemory = (signal?: AbortSignal): Promise<AIMemoryEntry[]> =>
  invoke('get_ai_memory', undefined, signal);

export const getMemoryHistory = (key: string, limit?: number, signal?: AbortSignal): Promise<MemoryHistoryResult> =>
  invoke('get_ai_memory_history', { key, limit: limit ?? null }, signal);

export const restoreMemoryRevision = (revisionId: string, signal?: AbortSignal): Promise<RestoreMemoryResult> =>
  invokeIpc('restore_memory_revision', { revision_id: revisionId }, signal);

export const setNotesForAi = (content: string, signal?: AbortSignal): Promise<{ key: string; updated: boolean }> =>
  invokeIpc('set_notes_for_ai', { content }, signal);

export const deleteNotesForAi = (signal?: AbortSignal): Promise<{ key: string; deleted: boolean }> =>
  invokeIpc('delete_notes_for_ai', {}, signal);

export const deleteAiMemoryEntry = (key: string, signal?: AbortSignal): Promise<{ key: string; deleted: boolean }> =>
  invokeIpc('delete_ai_memory_entry', { key }, signal);

interface CreateMemoryEntryResult {
  key: string;
  content: string;
  updated_at: string;
  ownership: 'human';
  created: boolean;
}

export const createMemoryEntry = (
  key: string,
  content: string,
  signal?: AbortSignal,
): Promise<CreateMemoryEntryResult> =>
  invokeIpc('create_memory_entry', { key, content }, signal);
