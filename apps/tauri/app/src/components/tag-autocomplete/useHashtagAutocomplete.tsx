// shared `#`-prefixed tag autocomplete for the
// quick-capture title and the task-detail title editor.
//
// The hook owns three things:
//   1. Watching the input's caret position + current value and
//      deriving the active hashtag fragment (via the pure helpers
//      in `tagAutocomplete.ts`).
//   2. Fetching `QK.allTags` via TanStack Query and ranking the
//      candidates with `filterTagCandidates`.
//   3. Keyboard navigation — ArrowUp/Down move the highlight,
//      Enter commits, Escape dismisses. Host components invoke
//      `onKeyDown` BEFORE their own Enter/submit handlers so we
//      intercept when the dropdown is open and defer to the host
//      otherwise.
//
// The render side is intentionally a small `<HashtagDropdown>` so
// both call sites share pixel-perfect styling without duplicating
// Tailwind classes.
import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useMemo,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type RefObject,
} from 'react';
import { useQuery } from '@tanstack/react-query';
import { themedSwatch } from '@/lib/colors/themedSwatch';
import { getAllTags } from '@/lib/ipc/tasks/queries';
import type { TagInfo } from '@/lib/ipc/tasks/queries';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_5_MIN } from '@/lib/query/timing';
import {
  filterTagCandidates,
  findActiveHashtagFragment,
  stripHashtagFragment,
  type HashtagFragment,
} from '@/lib/tags/autocomplete';
import type { useI18n } from '@/lib/i18n';

interface UseHashtagAutocompleteOptions {
  inputRef: RefObject<HTMLInputElement | null>;
  value: string;
  onAcceptTag: (tagDisplayName: string, nextTitle: string) => void;
  currentTags?: readonly string[];
  disabled?: boolean;
}

export interface HashtagAutocompleteState {
  open: boolean;
  fragment: HashtagFragment | null;
  suggestions: TagInfo[];
  highlightIndex: number;
  listboxId: string;
  activeOptionId: string | undefined;
  getOptionId: (index: number) => string;
  setHighlightIndex: (index: number) => void;
  onInputKeyDown: (event: ReactKeyboardEvent<HTMLInputElement>) => boolean;
  accept: (tag: TagInfo) => void;
  dismiss: () => void;
}

const MAX_SUGGESTIONS = 8;

/**
 * Hook version — consumers render `<HashtagDropdown>` themselves.
 *
 * Returns `open: true` when the caret is inside a `#fragment` and
 * there is at least one candidate tag left after filtering. The
 * caller uses `open` to decide whether to render the dropdown and
 * whether to swallow Enter.
 */
export function useHashtagAutocomplete(
  options: UseHashtagAutocompleteOptions,
): HashtagAutocompleteState {
  const { inputRef, value, onAcceptTag, currentTags, disabled } = options;
  const [caret, setCaret] = useState(0);
  const [dismissedFragmentKey, setDismissedFragmentKey] = useState<string | null>(null);
  const [highlightIndex, setHighlightIndex] = useState(0);
  const listboxId = useId();

  // Re-read caret on every value change — most host inputs are
  // fully controlled, so the caret after a keystroke lands at
  // `selectionStart`. We also listen for `selectionchange` to catch
  // mouse clicks and arrow-key navigation that move the caret
  // without changing the value.
  useLayoutEffect(() => {
    const el = inputRef.current;
    if (!el) return;
    setCaret(el.selectionStart ?? value.length);
  }, [inputRef, value]);

  useEffect(() => {
    const el = inputRef.current;
    if (!el) return;
    function read() {
      if (!el) return;
      // `document.activeElement` guard — `selectionchange` fires
      // globally; we only care when the watched input owns focus.
      if (document.activeElement !== el) return;
      setCaret(el.selectionStart ?? 0);
    }
    document.addEventListener('selectionchange', read);
    el.addEventListener('keyup', read);
    el.addEventListener('click', read);
    el.addEventListener('focus', read);
    return () => {
      document.removeEventListener('selectionchange', read);
      el.removeEventListener('keyup', read);
      el.removeEventListener('click', read);
      el.removeEventListener('focus', read);
    };
  }, [inputRef]);

  // Escape dismisses the exact fragment the user saw. A subsequent
  // edit creates a different fragment key, so matching suggestions can
  // re-open without requiring the caret to leave hashtag context first.
  const fragment = useMemo(
    () => (disabled ? null : findActiveHashtagFragment(value, caret)),
    [value, caret, disabled],
  );
  const fragmentKey = fragment
    ? `${fragment.hashStart}:${fragment.fragmentEnd}:${fragment.query}`
    : null;
  const fragmentDismissed = fragmentKey !== null && dismissedFragmentKey === fragmentKey;

  // Fetch all tags — same query key as the existing comma-tag
  // picker so a single fetch round-trips for both surfaces.
  const { data: allTags } = useQuery<TagInfo[]>({
    queryKey: QUERY_KEYS.allTags(),
    queryFn: ({ signal }) => getAllTags(signal),
    staleTime: STALE_5_MIN,
    enabled: !disabled,
  });

  const suggestions = useMemo(() => {
    if (!fragment || fragmentDismissed || !allTags) return [];
    return filterTagCandidates(allTags, fragment.query, currentTags ?? [], MAX_SUGGESTIONS);
  }, [fragment, fragmentDismissed, allTags, currentTags]);

  // Keep the highlight in bounds as the suggestion list reshapes.
  useEffect(() => {
    setHighlightIndex((prev) => {
      if (suggestions.length === 0) return 0;
      if (prev >= suggestions.length) return 0;
      return prev;
    });
  }, [suggestions.length]);

  const open = !fragmentDismissed && fragment !== null && suggestions.length > 0;
  const getOptionId = useCallback(
    (index: number) => `${listboxId}-option-${index}`,
    [listboxId],
  );
  const activeOptionId = open ? getOptionId(highlightIndex) : undefined;

  const accept = useCallback(
    (tag: TagInfo) => {
      if (!fragment) return;
      const { text } = stripHashtagFragment(value, fragment);
      onAcceptTag(tag.display_name, text);
      const el = inputRef.current;
      const nextCaret = fragment.hashStart;
      queueMicrotask(() => {
        if (el && document.activeElement === el) {
          try {
            el.setSelectionRange(nextCaret, nextCaret);
          } catch {
            // Non-text inputs don't support selection; harmless.
          }
        }
      });
    },
    [fragment, value, onAcceptTag, inputRef],
  );

  const dismiss = useCallback(() => {
    setDismissedFragmentKey(fragmentKey);
  }, [fragmentKey]);

  const onInputKeyDown = useCallback(
    (event: ReactKeyboardEvent<HTMLInputElement>): boolean => {
      if (!open) return false;
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        setHighlightIndex((prev) => (prev + 1) % suggestions.length);
        return true;
      }
      if (event.key === 'ArrowUp') {
        event.preventDefault();
        setHighlightIndex((prev) => (prev <= 0 ? suggestions.length - 1 : prev - 1));
        return true;
      }
      if (event.key === 'Enter' || event.key === 'Tab') {
        const chosen = suggestions[highlightIndex] ?? suggestions[0];
        if (chosen) {
          event.preventDefault();
          accept(chosen);
          return true;
        }
        return false;
      }
      if (event.key === 'Escape') {
        event.preventDefault();
        setDismissedFragmentKey(fragmentKey);
        return true;
      }
      return false;
    },
    [open, suggestions, highlightIndex, accept, fragmentKey],
  );

  return {
    open,
    fragment,
    suggestions,
    highlightIndex,
    listboxId,
    activeOptionId,
    getOptionId,
    setHighlightIndex,
    onInputKeyDown,
    accept,
    dismiss,
  };
}

/**
 * The dropdown primitive both call sites render. Anchored to the
 * input's bottom edge by positioning it absolutely inside a
 * `relative` wrapper in the host. Keeps the styling in one place so
 * quick-capture and task-detail can't drift apart.
 */
export function HashtagDropdown({
  state,
  t,
}: {
  state: HashtagAutocompleteState;
  t: ReturnType<typeof useI18n>['t'];
}) {
  if (!state.open) return null;
  return (
    <div
      id={state.listboxId}
      className="absolute top-full start-0 mt-1 z-[var(--z-popover)] bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] py-1 min-w-[var(--menu-min-w-md)] max-w-[16rem] animate-[fade-in_0.1s_ease-out]"
      role="listbox"
      aria-orientation="vertical"
      aria-label={t('tags.autocomplete.label')}
    >
      {state.suggestions.map((tag, idx) => (
        // <button role="option"> is a WAI-ARIA contradiction — listbox
        // children must be plain options with no implicit role conflict.
        // JAWS / NVDA narrate the native button role *and* the option
        // role, leading to double announcements ("button, option, list
        // item"). Use a <div role="option"> instead; pointer activation
        // happens on mouseDown (not click) so we fire before the input's
        // blur handler tears the dropdown down, and `preventDefault`
        // keeps focus on the input. Mirrors CommandPalette.tsx.
        <div
          key={tag.display_name}
          id={state.getOptionId(idx)}
          role="option"
          aria-selected={idx === state.highlightIndex}
          onMouseDown={(e) => {
            // MouseDown (not click) so we fire before the input's
            // blur handler tears the dropdown down.
            e.preventDefault();
            state.accept(tag);
          }}
          onMouseEnter={() => state.setHighlightIndex(idx)}
          className={`w-full flex items-center gap-2 text-xs px-2.5 py-1.5 text-start transition-colors cursor-pointer ${
            idx === state.highlightIndex
              ? 'bg-accent/10 text-text-primary'
              : 'text-text-secondary hover:bg-surface-3'
          }`}
        >
          <span aria-hidden="true" className="text-text-muted">#</span>
          {tag.color && (
            <span
              className="w-2 h-2 rounded-full shrink-0"
              style={{ backgroundColor: themedSwatch(tag.color, 'dot') }}
            />
          )}
          <span className="truncate">{tag.display_name}</span>
        </div>
      ))}
    </div>
  );
}
