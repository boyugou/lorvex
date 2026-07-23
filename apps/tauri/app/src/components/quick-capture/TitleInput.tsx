import { useState, type RefObject } from 'react';
import { MAX_TITLE_LENGTH } from '@lorvex/shared/validation';
import { isImeComposingEvent } from '@/lib/ime';
import type { useI18n } from '@/lib/i18n';
import { AutosizingTextarea } from '../ui/AutosizingTextarea';
import { ValidatedField } from '../ui/ValidatedField';
import {
  HashtagDropdown,
  useHashtagAutocomplete,
} from '../tag-autocomplete/useHashtagAutocomplete';
import {
  appendQuickCaptureTagDraft,
  parseQuickCaptureTagDraft,
} from './tagDraft';

interface TitleInputProps {
  title: string;
  setTitle: (value: string) => void;
  body: string;
  setBody: (value: string) => void;
  showBody: boolean;
  setShowBody: (show: boolean) => void;
  isComposing: boolean;
  setIsComposing: (composing: boolean) => void;
  onSubmit: () => void;
  onSubmitAndContinue: () => void;
  canSubmit: boolean;
  inputRef: RefObject<HTMLInputElement | null>;
  isMobile: boolean;
  t: ReturnType<typeof useI18n>['t'];
  // hashtag autocomplete. When the user types `#foo`
  // mid-title and picks a tag, we write it into the comma-separated
  // `tagsInput` draft so the existing submit path (which already
  // parses comma tokens in useQuickCaptureForm.doSubmit) picks it
  // up. The title gets the `#foo` fragment stripped.
  tagsInput: string;
  setTagsInput: (value: string) => void;
}

export default function TitleInput({
  title,
  setTitle,
  body,
  setBody,
  showBody,
  setShowBody,
  isComposing,
  setIsComposing,
  onSubmit,
  onSubmitAndContinue,
  canSubmit,
  inputRef,
  isMobile,
  t,
  tagsInput,
  setTagsInput,
}: TitleInputProps) {
  const [attempted, setAttempted] = useState(false);
  const titleError = attempted && !title.trim() ? t('capture.titleRequired') : null;

  // Derive the list of tags already chosen (from the comma-input
  // draft) so the hashtag dropdown hides dupes.
  const currentTags = parseQuickCaptureTagDraft(tagsInput);

  const hashtag = useHashtagAutocomplete({
    inputRef,
    value: title,
    disabled: isComposing,
    currentTags,
    onAcceptTag: (tagName, nextTitle) => {
      setTitle(nextTitle);
      setTagsInput(appendQuickCaptureTagDraft(tagsInput, tagName));
    },
  });

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>): void {
    // Hashtag dropdown consumes Arrow/Enter/Escape/Tab when open.
    // Returns true when it handled the event — bail early so we
    // don't ALSO fire the submit path.
    if (hashtag.onInputKeyDown(e)) return;
    if (isComposing || isImeComposingEvent(e.nativeEvent as KeyboardEvent & { keyCode?: number; which?: number })) return;
    if (e.key === 'Enter') {
      if (!title.trim()) {
        setAttempted(true);
        return;
      }
      if (canSubmit) {
        if ((e.metaKey || e.ctrlKey) && e.shiftKey) {
          e.preventDefault();
          onSubmitAndContinue();
        } else {
          onSubmit();
        }
      }
    }
  }

  return (
    <div className="p-4 pb-2">
      <ValidatedField
        label={t('capture.placeholder')}
        showLabel={false}
        error={titleError}
      >
        {({ fieldProps }) => (
          <div className="relative">
            <input
              {...fieldProps}
              ref={inputRef}
              type="text"
              value={title}
              onChange={e => setTitle(e.target.value)}
              onCompositionStart={() => setIsComposing(true)}
              onCompositionEnd={() => setIsComposing(false)}
              onKeyDown={handleKeyDown}
              onBlur={() => {
                if (!title.trim()) setAttempted(true);
              }}
              maxLength={MAX_TITLE_LENGTH}
              placeholder={t('capture.placeholder')}
              aria-label={t('capture.placeholder')}
              role="combobox"
              aria-autocomplete="list"
              aria-expanded={hashtag.open}
              aria-haspopup="listbox"
              aria-controls={hashtag.listboxId}
              aria-activedescendant={hashtag.activeOptionId}
              className={`${fieldProps.className} w-full bg-transparent text-text-primary placeholder:text-text-muted outline-hidden focus-ring-soft ${
                isMobile ? 'text-base' : 'text-lg'
              }`}
            />
            <HashtagDropdown state={hashtag} t={t} />
          </div>
        )}
      </ValidatedField>
      {showBody ? (
        <AutosizingTextarea
          value={body}
          onChange={e => setBody(e.target.value)}
          onCompositionStart={() => setIsComposing(true)}
          onCompositionEnd={() => setIsComposing(false)}
          placeholder={t('capture.notesPlaceholder')}
          aria-label={t('capture.notesPlaceholder')}
          minRows={3}
          maxRows={10}
          data-theme-form-control="true"
          className="w-full mt-2 bg-surface-3/50 text-text-secondary text-sm px-2.5 py-2 rounded-r-control border border-surface-3 outline-hidden focus-ring-soft placeholder:text-text-muted/60"
        />
      ) : (
        <button
          type="button"
          onClick={() => setShowBody(true)}
          className="mt-1.5 text-text-muted hover:text-text-secondary text-xs transition-colors border border-dashed border-card rounded-r-control px-2 py-1 hover:bg-surface-3/50 focus-ring-soft"
        >
          + {t('capture.addNotes')}
        </button>
      )}
    </div>
  );
}
