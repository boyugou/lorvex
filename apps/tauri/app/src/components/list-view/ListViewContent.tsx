import { useCallback, useMemo, useRef, type RefObject } from 'react';

import { useScrollRestore } from '@/lib/useScrollRestore';
import ModuleStatePanel from '../ui/ModuleStatePanel';
import { SearchIcon } from '../ui/icons';

import { useI18n } from '@/lib/i18n';
import { type ListViewContentProps, ListViewProvider, useListView } from './ListViewContext';

import { AddTaskInput } from './AddTaskInput';
import { CompletedTasksSection } from './CompletedTasksSection';
import { ListViewHeader } from './ListViewHeader';
import { ListViewToolbar } from './ListViewToolbar';
import { EmptyList } from './ListViewStates';
import { OpenTaskList } from './OpenTaskList';

// Re-export so ListView.tsx can import from this file.
export { ListViewLoadError, LoadingState } from './ListViewStates';
export type { ListViewContentProps } from './ListViewContext';

// ---------------------------------------------------------------------------
// Component (outer wrapper — provides context)
// ---------------------------------------------------------------------------

export function ListViewContent(props: ListViewContentProps): React.JSX.Element {
  // Owned here so the provider value carries a stable ref that
  // descendants (OpenTaskList) can read for virtualization. The ref
  // is wired onto the scroll container inside `ListViewContentInner`.
  const scrollContainerRef = useRef<HTMLDivElement | null>(null);
  return (
    <ListViewProvider value={{ ...props, scrollContainerRef }}>
      <ListViewContentInner scrollContainerRef={scrollContainerRef} />
    </ListViewProvider>
  );
}

// ---------------------------------------------------------------------------
// Inner component — reads everything from context
// ---------------------------------------------------------------------------

function ListViewContentInner({
  scrollContainerRef,
}: {
  scrollContainerRef: RefObject<HTMLDivElement | null>;
}): React.JSX.Element {
  const { t } = useI18n();
  const {
    data,
    inputRef,
    draft,
    openTasks,
    isFilterActive,
    totalOpenCount,
  } = useListView();

  const { list } = data;
  const scroll = useScrollRestore(`list-${list.id}`);
  const totalEstimatedMinutes = useMemo(
    () => openTasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [openTasks],
  );

  // Fan the scroll-container DOM node out to both consumers: the
  // restore hook (persists scrollTop across mounts) and the
  // virtualization ref (measures rows against this element).
  const setScrollNode = useCallback(
    (node: HTMLDivElement | null) => {
      (scroll.ref as React.MutableRefObject<HTMLDivElement | null>).current = node;
      scrollContainerRef.current = node;
    },
    [scroll.ref, scrollContainerRef],
  );

  const showEmptyState = openTasks.length === 0 && draft === '';
  const showFilterNoMatch = showEmptyState && isFilterActive && totalOpenCount > 0;

  return (
    <>
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <ListViewHeader />
        <ListViewToolbar totalEstimatedMinutes={totalEstimatedMinutes} />
      </header>

      <div ref={setScrollNode} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8">
        {showEmptyState ? (
          showFilterNoMatch ? (
            <ModuleStatePanel icon={<SearchIcon className="w-9 h-9" />} title={t('allTasks.emptyNoMatch')} subtitle={t('allTasks.emptySearchHint')} />
          ) : (
            <EmptyList listName={list.name} onFocusInput={() => inputRef.current?.focus()} />
          )
        ) : (
          <OpenTaskList />
        )}

        <AddTaskInput />

        <CompletedTasksSection />
      </div>
    </>
  );
}
