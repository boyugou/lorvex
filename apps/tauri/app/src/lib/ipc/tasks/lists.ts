import { invoke, invokeIpc } from '../core';
import type { DeleteListResult } from '../lists/models';

import type {
  ListWithCount,
  ListWithTasks,
  TaskList,
} from './models';

export const createList = (args: {
  name: string;
  color?: string | null | undefined;
  icon?: string | null | undefined;
  description?: string | null;
}, signal?: AbortSignal): Promise<TaskList> =>
  invokeIpc('create_list', args, signal);

export const updateList = (args: {
  id: string;
  name?: string;
  color?: string | null;
  icon?: string | null;
  description?: string | null;
}, signal?: AbortSignal): Promise<TaskList> =>
  invokeIpc('update_list', { args }, signal);

export const getAllLists = (signal?: AbortSignal): Promise<ListWithCount[]> =>
  invoke('get_all_lists', undefined, signal);

export const getListWithTasks = (id: string, signal?: AbortSignal): Promise<ListWithTasks> =>
  invoke('get_list_with_tasks', { id }, signal);

export const deleteList = (id: string, signal?: AbortSignal): Promise<DeleteListResult> =>
  invokeIpc('delete_list', { id }, signal);

/**
 * Mirrors the `ShelveListResult` Rust struct in `lists.rs`.
 *
 * - `shelved_count` — number of tasks successfully flipped to `someday`
 *   (equals `shelved_task_ids.length`).
 * - `shelved_task_ids` — IDs that were actually transitioned.
 * - `skipped_task_ids` — IDs that were enumerated as `open` at SELECT
 *   time but couldn't be shelved (concurrent peer apply, or the LWW
 *   gate rejected the freshly-minted local version). The UI can use
 *   this to surface a "couldn't shelve N tasks" message — those rows
 *   will reconverge on the next sync apply tick.
 */
interface ShelveListResult {
  shelved_count: number;
  shelved_task_ids: string[];
  skipped_task_ids: string[];
}

export const shelveList = (listId: string, signal?: AbortSignal): Promise<ShelveListResult> =>
  invokeIpc('shelve_list', { list_id: listId }, signal);
