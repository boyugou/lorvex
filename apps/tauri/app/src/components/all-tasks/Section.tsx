import { type MouseEvent as ReactMouseEvent } from 'react';
import { InteractiveTaskCard } from '../task-card/InteractiveTaskCard';
import { VirtualSectionHeader } from './VirtualSectionHeader';
import type { VirtualRow } from '../AllTasksView';

/** Approximate row heights for the virtualizer estimateSize callback. */
export const HEADER_HEIGHT = 36;
export const TASK_ROW_HEIGHT = 50;
export const SECTION_GAP_HEIGHT = 24;

/**
 * Renders one virtual row inside the AllTasks body. The view shell
 * owns the virtualizer + scroll container and hands each row down with
 * the absolute-position transforms already applied; this component
 * just dispatches on `row.kind` and renders the appropriate child.
 *
 * The orchestrator passes selection/keyboard state through directly
 * rather than via context so the row can stay a function component
 * without subscribing to selection updates it doesn't read.
 */
export function SectionRow({
  row,
  selectionMode,
  selectedIds,
  bulkAction,
  focusedId,
  onSelectTask,
  onToggleSelected,
  onClickWithModifiers,
  getSectionToggleHandler,
}: {
  row: VirtualRow;
  selectionMode: boolean;
  selectedIds: Set<string>;
  bulkAction: unknown;
  focusedId: string | null;
  onSelectTask?: ((taskId: string) => void) | undefined;
  onToggleSelected: (taskId: string) => void;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
  getSectionToggleHandler: (sectionKey: string) => () => void;
}) {
  if (row.kind === 'section-gap') {
    return <div style={{ height: SECTION_GAP_HEIGHT }} />;
  }
  if (row.kind === 'section-header') {
    return (
      <VirtualSectionHeader
        section={row.section}
        collapsed={row.collapsed}
        onToggleCollapse={getSectionToggleHandler(row.section.key)}
      />
    );
  }
  return (
    <div className={`py-0.5 ${row.completed ? 'opacity-70' : ''}`}>
      <InteractiveTaskCard
        task={row.task}
        selectionMode={selectionMode}
        selected={selectedIds.has(row.task.id)}
        bulkBusy={bulkAction !== null}
        completed={row.completed}
        focused={focusedId === row.task.id}
        hasSelection={selectedIds.size > 0}
        onToggleSelected={onToggleSelected}
        onSelect={onSelectTask}
        onClickWithModifiers={onClickWithModifiers}
      />
    </div>
  );
}
