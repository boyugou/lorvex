/**
 * device-local saved filter presets IPC wrappers.
 *
 * Each list-shaped view (AllTasks, Someday, Upcoming, Kanban,
 * Eisenhower) persists a named snapshot of its filter state through
 * these four commands. `filter_json` is opaque — each view owns its
 * own serialize / deserialize pair.
 *
 * Kept in a dedicated module so the file stays compact and the
 * surface is easy to find when a new view adopts saved queries.
 */

import { invoke, invokeIpc } from './core';

export type SavedQueryViewType =
  | 'AllTasks'
  | 'Someday'
  | 'Upcoming'
  | 'Kanban'
  | 'Eisenhower';

export interface SavedQuery {
  id: string;
  view_type: SavedQueryViewType;
  name: string;
  filter_json: string;
  created_at: string;
  updated_at: string;
}

export const saveQuery = (
  viewType: SavedQueryViewType,
  name: string,
  filterJson: string,
  signal?: AbortSignal,
): Promise<SavedQuery> =>
  invokeIpc(
    'save_query',
    { view_type: viewType, name, filter_json: filterJson },
    signal,
  );

export const listSavedQueries = (
  viewType: SavedQueryViewType,
  signal?: AbortSignal,
): Promise<SavedQuery[]> =>
  invoke('list_saved_queries', { view_type: viewType }, signal);

export const loadSavedQuery = (
  id: string,
  signal?: AbortSignal,
): Promise<SavedQuery | null> =>
  invoke('load_saved_query', { id }, signal);

export const deleteSavedQuery = (id: string, signal?: AbortSignal): Promise<void> =>
  invokeIpc('delete_saved_query', { id }, signal);
