import { Suspense } from 'react';
import { MAX_BODY_LENGTH } from '@lorvex/shared/validation';

import ErrorBoundary from '@/components/ErrorBoundary';
import { useI18n } from '@/lib/i18n';
import MilkdownEditor from '@/components/ui/MilkdownEditor.lazy';
import { renderInlineMarkdown } from './inlineMarkdown';

interface TaskBodyContentProps {
  bodyDraft: string;
  notesPlaceholder: string;
  onChange: (markdown: string) => void;
  taskId: string;
}

export function TaskBodyContent({
  bodyDraft,
  notesPlaceholder,
  onChange,
  taskId,
}: TaskBodyContentProps) {
  const { t } = useI18n();
  // ErrorBoundary wraps Suspense so a chunk-load or
  // async-after-suspend failure in the lazy editor surfaces a retry
  // affordance instead of stranding the user on a shimmer that never
  // resolves. Keyed on taskId so switching tasks clears stale errors.
  return (
    <ErrorBoundary resetKeys={['task-body-editor', taskId]}>
      <Suspense fallback={<div className="text-text-muted text-sm p-1">{renderInlineMarkdown(notesPlaceholder)}</div>}>
        <MilkdownEditor
          key={taskId}
          defaultValue={bodyDraft}
          onChange={onChange}
          placeholder={notesPlaceholder}
          maxLength={MAX_BODY_LENGTH}
          ariaLabel={t('task.bodyEditorAriaLabel')}
        />
      </Suspense>
    </ErrorBoundary>
  );
}
