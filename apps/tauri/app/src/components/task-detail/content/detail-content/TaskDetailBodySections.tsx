import TaskChecklistEditor from '@/components/task-detail/TaskChecklistEditor';
import TaskNotesEditor from '@/components/task-detail/task-notes-editor/TaskNotesEditor';
import { TaskUnifiedMetaCard } from '@/components/task-detail/metadata-editor/TaskUnifiedMetaCard';
import type { TaskDetailControllerState } from '@/components/task-detail/support';
import { TaskDetailAiNotes } from '../TaskDetailInfoSections';
import { TaskHistorySection } from '../TaskHistorySection';
import { TaskDetailInlineTags } from './TaskDetailInlineTags';
import { TaskDetailMoreSection } from './TaskDetailMoreSection';

export function TaskDetailBodySections({
  actionBarController,
  bodyDraft,
  controller,
  handleBodyDirtyChange,
  handleBodyDraftChange,
  isActionable,
  locale,
  overdue,
  persistBody,
  refetchTask,
  saveMetaPatch,
  task,
  taskId,
  t,
}: {
  actionBarController: TaskDetailControllerState & { task: NonNullable<TaskDetailControllerState['task']> };
  bodyDraft: string;
  controller: TaskDetailControllerState;
  handleBodyDirtyChange: (dirty: boolean) => void;
  handleBodyDraftChange: (value: string) => void;
  isActionable: boolean;
  locale: string;
  overdue: boolean;
  persistBody: (draft?: string) => Promise<boolean>;
  refetchTask: () => Promise<unknown>;
  saveMetaPatch: TaskDetailControllerState['saveMetaPatch'];
  task: NonNullable<TaskDetailControllerState['task']>;
  taskId: string;
  t: TaskDetailControllerState['t'];
}) {
  return (
    <>
      <TaskUnifiedMetaCard
        task={task}
        overdue={overdue}
        locale={locale}
        t={t}
        onSave={async (patch) => { await saveMetaPatch(patch); }}
        isActionable={isActionable}
        onDefer={actionBarController.handleDefer}
      />

      <TaskDetailInlineTags task={task} controller={controller} />

      <TaskDetailAiNotes controller={{ t, task }} />

      <TaskNotesEditor
        taskId={taskId}
        bodyDraft={bodyDraft}
        onBodyDraftChange={handleBodyDraftChange}
        onBodyDirtyChange={handleBodyDirtyChange}
        persistBody={persistBody}
        notesPlaceholder={t('capture.notesPlaceholder')}
        notesLabel={t('task.notes')}
      />

      <TaskChecklistEditor
        taskId={taskId}
        items={task.checklist_items}
        refetchTask={refetchTask}
      />

      <div className="border-t border-card" />

      <TaskDetailMoreSection
        actionBarController={actionBarController}
        controller={controller}
        taskId={taskId}
        t={t}
      />

      <TaskHistorySection taskId={taskId} />
    </>
  );
}
