import { useState } from 'react';
import { MAX_TITLE_LENGTH } from '@lorvex/shared/validation';
import { quickCapture } from '@/lib/ipc/tasks/mutations/quickCapture';
import { reportClientError } from '@/lib/errors/errorLogging';
import { toast } from '@/lib/notifications/toast';
import type { TranslationKey } from '@/lib/i18n';
import { ValidatedField } from '../ui/ValidatedField';

export function InlineAddTask({
  date,
  t,
  onCreated,
}: {
  date: string;
  t: (k: TranslationKey) => string;
  onCreated: () => void;
}) {
  // a11y: the inline add field was uncontrolled; an empty
  // submit silently returned with no feedback. We now run a controlled
  // input + `aria-invalid` wiring so screen readers hear "invalid"
  // when the user presses Enter on an empty field, matching the
  // validation contract already used by the quick-capture main field.
  const [value, setValue] = useState('');
  const [attempted, setAttempted] = useState(false);
  const [adding, setAdding] = useState(false);
  const titleError = attempted && !value.trim() ? t('capture.titleRequired') : null;

  const handleSubmit = async () => {
    const title = value.trim();
    if (!title) {
      setAttempted(true);
      return;
    }
    if (adding) return;
    setAdding(true);
    try {
      await quickCapture({ title, dueDate: date });
      setValue('');
      setAttempted(false);
      onCreated();
    } catch (error) {
      reportClientError('upcoming.inlineAdd', 'Failed to add task', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setAdding(false);
    }
  };

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void handleSubmit();
      }}
      className="mt-1"
    >
      <ValidatedField
        label={t('upcoming.addTask')}
        showLabel={false}
        error={titleError}
      >
        {({ fieldProps }) => (
          <input
            {...fieldProps}
            type="text"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            disabled={adding}
            maxLength={MAX_TITLE_LENGTH}
            placeholder={`+ ${t('upcoming.addTask')}`}
            aria-label={t('upcoming.addTask')}
            className={`${fieldProps.className} w-full text-xs bg-transparent text-text-muted hover:text-text-secondary focus:text-text-primary px-4 py-1.5 rounded-r-card border border-dashed border-card hover:border-surface-3 focus:border-accent/40 outline-hidden focus-ring-soft placeholder:text-text-muted/50 disabled:opacity-50 transition-colors`}
            onKeyDown={(e) => {
              if (e.key === 'Escape') e.currentTarget.blur();
            }}
          />
        )}
      </ValidatedField>
    </form>
  );
}
