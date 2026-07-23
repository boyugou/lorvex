import { useCallback, useEffect, useRef } from 'react';

import { TaskBodyContent } from './TaskBodyContent';
import {
  createBrowserTaskNotesSaveTimerHost,
  createTaskNotesSaveState,
  flushTaskNotesSave,
  scheduleTaskNotesSave,
  type TaskNotesSaveState,
} from './TaskNotesEditor.runtime';

interface TaskNotesEditorProps {
  taskId: string;
  bodyDraft: string;
  onBodyDraftChange: (next: string) => void;
  onBodyDirtyChange: (next: boolean) => void;
  persistBody: (draft?: string) => Promise<boolean>;
  notesPlaceholder: string;
  notesLabel: string;
}

const taskNotesSaveTimerHost = createBrowserTaskNotesSaveTimerHost();

export default function TaskNotesEditor({
  taskId,
  bodyDraft,
  onBodyDraftChange,
  onBodyDirtyChange,
  persistBody,
  notesPlaceholder,
  notesLabel,
}: TaskNotesEditorProps) {
  const saveStateRef = useRef<TaskNotesSaveState>(createTaskNotesSaveState());
  // Capture BOTH the persistBody function and the markdown at scheduling
  // time so the flush-on-task-switch cleanup saves the edited task's draft
  // via the edited task's persistBody — not the newly-mounted task's. A
  // prior version kept only a ref to `persistBody` updated during render,
  // which meant by the time the effect cleanup for task A ran, the ref
  // already pointed at task B's persistBody (render runs before cleanup).
  // The result was A's pending keystrokes being dropped and a no-op
  // write against B.
  const handleChange = useCallback((markdown: string) => {
    onBodyDraftChange(markdown);
    onBodyDirtyChange(true);
    scheduleTaskNotesSave({
      state: saveStateRef.current,
      timerHost: taskNotesSaveTimerHost,
      pending: { persistBody, markdown },
    });
  }, [onBodyDraftChange, onBodyDirtyChange, persistBody]);

  // Flush on unmount or task switch — uses the snapshot captured when the
  // timer was scheduled, so the draft is always written against the task
  // that originated it.
  useEffect(() => () => {
    flushTaskNotesSave(
      saveStateRef.current,
      taskNotesSaveTimerHost.clearTimeout,
    );
  }, [taskId]);

  return (
    <section className="flex flex-col min-h-0">
      <span className="text-text-muted/60 text-2xs font-medium uppercase tracking-wide mb-1.5">{notesLabel}</span>
      <div className="rounded-r-control p-3 flex flex-col min-h-[80px] max-h-[400px] overflow-y-auto border border-card bg-surface-2/40 focus-within:border-accent/20 focus-within:bg-surface-2/60 transition-colors">
        <TaskBodyContent
          taskId={taskId}
          bodyDraft={bodyDraft}
          onChange={handleChange}
          notesPlaceholder={notesPlaceholder}
        />
      </div>
    </section>
  );
}
