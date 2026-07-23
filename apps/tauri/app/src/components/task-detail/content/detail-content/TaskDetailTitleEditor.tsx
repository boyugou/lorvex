import type { KeyboardEvent, RefObject } from 'react';
import { MAX_TITLE_LENGTH } from '@lorvex/shared/validation';

import type { TaskDetailControllerState } from '@/components/task-detail/support';
import {
  HashtagDropdown,
  useHashtagAutocomplete,
} from '@/components/tag-autocomplete/useHashtagAutocomplete';

export function TaskDetailTitleEditor({
  handleTitleBlur,
  handleTitleChange,
  handleTitleCompositionEnd,
  handleTitleCompositionStart,
  handleTitleKeyDown,
  hashtag,
  isComplete,
  resolvedTitleRef,
  t,
  titleDraft,
}: {
  handleTitleBlur: () => void;
  handleTitleChange: (value: string) => void;
  handleTitleCompositionEnd: () => void;
  handleTitleCompositionStart: () => void;
  handleTitleKeyDown: (event: KeyboardEvent<HTMLInputElement>) => void;
  hashtag: ReturnType<typeof useHashtagAutocomplete>;
  isComplete: boolean;
  resolvedTitleRef: RefObject<HTMLInputElement | null>;
  t: TaskDetailControllerState['t'];
  titleDraft: string;
}) {
  return (
    <div className="relative">
      <input
        ref={resolvedTitleRef}
        value={titleDraft}
        onChange={(event) => handleTitleChange(event.target.value)}
        onBlur={handleTitleBlur}
        onCompositionStart={handleTitleCompositionStart}
        onCompositionEnd={handleTitleCompositionEnd}
        onKeyDown={(event) => {
          if (hashtag.onInputKeyDown(event)) return;
          handleTitleKeyDown(event);
        }}
        maxLength={MAX_TITLE_LENGTH}
        aria-label={t('task.title')}
        placeholder={t('task.title')}
        role="combobox"
        aria-autocomplete="list"
        aria-expanded={hashtag.open}
        aria-haspopup="listbox"
        aria-controls={hashtag.listboxId}
        aria-activedescendant={hashtag.activeOptionId}
        className={`w-full text-lg font-semibold bg-transparent border-none outline-hidden pb-1 border-b border-transparent hover:border-card focus:border-accent/60 focus-visible:border-accent focus-visible:border-b-2 rounded-r-control focus-ring-soft transition-[border-color] placeholder:text-text-muted/30 hover:placeholder:text-text-muted/50 ${
          isComplete ? 'text-text-muted line-through' : 'text-text-primary'
        }`}
      />
      <HashtagDropdown state={hashtag} t={t} />
    </div>
  );
}
