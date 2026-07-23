import { createContext, useContext, type MouseEvent as ReactMouseEvent, type RefObject } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { useBulkActions } from '@/lib/tasks/useBulkActions';
import type { PriorityFilterValue } from '@/lib/tasks/priorityFilter';

import type { SortDirection, SortKey } from '../all-tasks/types';
import type { ListViewData, ListViewProps } from './support';

// ---------------------------------------------------------------------------
// Context value — mirrors the former ListViewContentProps interface
// ---------------------------------------------------------------------------

export interface ListViewContentProps {
  data: ListViewData;
  inputRef: RefObject<HTMLInputElement | null>;
  /**
   * Scroll-container ref exposed to descendants. The virtualized
   * OpenTaskList uses this as its scroll element so it can
   * measure + window rows against the same overflow container that
   * owns scroll restoration. Injected by `ListViewContent` when it
   * renders the provider; callers never set this themselves.
   */
  scrollContainerRef?: RefObject<HTMLDivElement | null> | undefined;
  draft: string;
  adding: boolean;
  deleting: boolean;
  renaming: boolean;
  renameSaving: boolean;
  usesMobileLayout: boolean;
  openTasks: Task[];
  completedTasks: Task[];
  onDraftChange: (value: string) => void;
  onAdd: () => void;
  onDeleteList: () => void;
  onRename: (newName: string) => void;
  onStartRename: () => void;
  onCancelRename: () => void;
  search: string;
  onSearchChange: (value: string) => void;
  onSelectTask?: ListViewProps['onSelectTask'] | undefined;
  focusedTaskId?: string | null | undefined;
  sortKey: SortKey;
  sortDirection: SortDirection;
  onSortKeyChange: (key: SortKey) => void;
  onToggleSortDirection: () => void;
  filterPriority: PriorityFilterValue;
  onFilterPriorityChange: (priority: PriorityFilterValue) => void;
  allTags: string[];
  selectedTags: Set<string>;
  onToggleTag: (tag: string) => void;
  onClearTagFilter: () => void;
  isFilterActive: boolean;
  totalOpenCount: number;
  selectionMode: boolean;
  selectedIds: Set<string>;
  onToggleSelected: (id: string) => void;
  onSelectAll: () => void;
  onClearSelection: () => void;
  onSetSelectionMode: (enabled: boolean) => void;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
  bulk: ReturnType<typeof useBulkActions>;
}

// ---------------------------------------------------------------------------
// React context + hook
// ---------------------------------------------------------------------------

const ListViewContext = createContext<ListViewContentProps | null>(null);

export function ListViewProvider({
  value,
  children,
}: {
  value: ListViewContentProps;
  children: React.ReactNode;
}): React.JSX.Element {
  return (
    <ListViewContext.Provider value={value}>
      {children}
    </ListViewContext.Provider>
  );
}

export function useListView(): ListViewContentProps {
  const ctx = useContext(ListViewContext);
  if (!ctx) {
    throw new Error('useListView must be used within a <ListViewProvider>');
  }
  return ctx;
}
