import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type FocusEvent,
  type KeyboardEvent,
} from 'react';
import { createPortal } from 'react-dom';
import { useQuery } from '@tanstack/react-query';
import { XIcon } from '@/components/ui/icons';
import { themedSwatch } from '@/lib/colors/themedSwatch';
import { getAllTags } from '@/lib/ipc/tasks/queries';
import type { TagInfo } from '@/lib/ipc/tasks/queries';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_5_MIN } from '@/lib/query/timing';
import { ToggleChip } from '@/components/ui/ToggleChip';
import {
  createBrowserCompactToolbarFocusTimerHost,
  deferCompactToolbarFocus,
} from '../CompactToolbar.runtime';
import { resolveAnchoredPopupPosition } from '@/components/ui/portalDropdown.runtime';
import {
  clampQuickCaptureTagDraftInput,
  currentQuickCaptureTagToken,
  parseQuickCaptureTagDraft,
  replaceCurrentQuickCaptureTagToken,
} from '../tagDraft';
import { resolveTagAutocompleteEscapeAction } from './TagsToggle.runtime';
import type { CompactToolbarTranslate } from './types';
import { QUICK_CAPTURE_POPOVER_Z_CLASS, QUICK_CAPTURE_POPOVER_SHELL_CLASS } from './popoverLayer';

const MAX_SUGGESTIONS = 8;
const TAG_SUGGESTIONS_POPUP_WIDTH_PX = 224;
const TAG_SUGGESTIONS_POPUP_MIN_WIDTH_PX = 160;
const TAG_SUGGESTIONS_OPTION_HEIGHT_PX = 30;
const TAG_SUGGESTIONS_VERTICAL_PADDING_PX = 8;
const TAG_SUGGESTIONS_VIEWPORT_PADDING_PX = 8;
const compactToolbarFocusTimerHost = createBrowserCompactToolbarFocusTimerHost();

export function TagsToggle({
  tagsInput,
  setTagsInput,
  t,
}: {
  tagsInput: string;
  setTagsInput: (v: string) => void;
  t: CompactToolbarTranslate;
}) {
  const [expanded, setExpanded] = useState(false);
  const [focused, setFocused] = useState(false);
  const [highlightIndex, setHighlightIndex] = useState(-1);
  const inputRef = useRef<HTMLInputElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const tagSuggestionsListboxId = useId();
  const [panelPos, setPanelPos] = useState<{ top: number; left: number; width: number } | null>(null);

  // Fetch all tags; invalidated by the tag/task_tag entity map in queryKeys.ts
  // so MCP-side tag creates refresh the autocomplete immediately.
  const { data: allTags } = useQuery<TagInfo[]>({
    queryKey: QUERY_KEYS.allTags(),
    queryFn: ({ signal }) => getAllTags(signal),
    staleTime: STALE_5_MIN,
  });

  // Auto-expand if tags are already set
  const showInput = expanded || tagsInput.length > 0;

  // Compute suggestions
  const suggestions = useMemo(() => {
    if (!allTags || !focused) return [];
    const token = currentQuickCaptureTagToken(tagsInput).toLowerCase();
    const alreadySelected = new Set(parseQuickCaptureTagDraft(tagsInput).map((tag) => tag.toLowerCase()));

    return allTags
      .filter((tag) => {
        const name = tag.display_name.toLowerCase();
        // Hide already-selected tags
        if (alreadySelected.has(name)) return false;
        // If there's no token yet, show all available tags
        if (!token) return true;
        // Prefix match
        return name.startsWith(token) || name.includes(token);
      })
      .slice(0, MAX_SUGGESTIONS);
  }, [allTags, tagsInput, focused]);

  const showDropdown = focused && suggestions.length > 0;
  const activeSuggestionId = showDropdown && highlightIndex >= 0
    ? `${tagSuggestionsListboxId}-option-${highlightIndex}`
    : undefined;

  useLayoutEffect(() => {
    if (!showDropdown) {
      setPanelPos(null);
      return;
    }

    const updatePanelPosition = () => {
      const rect = inputRef.current?.getBoundingClientRect();
      if (!rect) return;
      const availableWidth = Math.max(
        0,
        window.innerWidth - TAG_SUGGESTIONS_VIEWPORT_PADDING_PX * 2,
      );
      const popupWidth = availableWidth < TAG_SUGGESTIONS_POPUP_MIN_WIDTH_PX
        ? availableWidth
        : Math.min(TAG_SUGGESTIONS_POPUP_WIDTH_PX, availableWidth);
      const popupHeight = suggestions.length * TAG_SUGGESTIONS_OPTION_HEIGHT_PX
        + TAG_SUGGESTIONS_VERTICAL_PADDING_PX;
      const position = resolveAnchoredPopupPosition({
        rect,
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
        popupWidth,
        popupHeight,
        viewportPadding: TAG_SUGGESTIONS_VIEWPORT_PADDING_PX,
        flipVertically: true,
      });
      setPanelPos({ ...position, width: popupWidth });
    };

    updatePanelPosition();
    window.addEventListener('resize', updatePanelPosition);
    document.addEventListener('scroll', updatePanelPosition, { capture: true, passive: true });
    return () => {
      window.removeEventListener('resize', updatePanelPosition);
      document.removeEventListener('scroll', updatePanelPosition, true);
    };
  }, [showDropdown, suggestions.length]);

  // Reset highlight when suggestions change
  useEffect(() => {
    setHighlightIndex(-1);
  }, [suggestions.length, tagsInput]);

  const selectSuggestion = useCallback((tag: TagInfo) => {
    setTagsInput(replaceCurrentQuickCaptureTagToken(tagsInput, tag.display_name));
    inputRef.current?.focus();
  }, [tagsInput, setTagsInput]);

  function handleToggle() {
    if (showInput && !tagsInput) {
      setExpanded(false);
    } else {
      setExpanded(true);
      deferCompactToolbarFocus(
        compactToolbarFocusTimerHost,
        () => inputRef.current?.focus(),
      );
    }
  }

  function handleKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Escape') {
      const action = resolveTagAutocompleteEscapeAction({ showDropdown, showInput });
      if (action !== 'none') {
        e.preventDefault();
        e.stopPropagation();
      }
      if (action === 'close-suggestions') {
        setFocused(false);
      } else if (action === 'collapse-input') {
        setFocused(false);
        setExpanded(false);
        inputRef.current?.blur();
      }
      return;
    }

    if (!showDropdown) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setHighlightIndex((prev) => (prev + 1) % suggestions.length);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setHighlightIndex((prev) => (prev <= 0 ? suggestions.length - 1 : prev - 1));
    } else if (e.key === 'Enter' && highlightIndex >= 0 && highlightIndex < suggestions.length) {
      e.preventDefault();
      const selected = suggestions[highlightIndex];
      if (selected) selectSuggestion(selected);
    }
  }

  function handleBlur(e: FocusEvent) {
    // Don't close if focus moves within the container (e.g., clicking a suggestion)
    if (containerRef.current?.contains(e.relatedTarget as Node)) return;
    setFocused(false);
    if (!tagsInput) setExpanded(false);
  }

  return (
    <div className="flex items-center gap-1" ref={containerRef}>
      <ToggleChip
        onClick={handleToggle}
        selected={Boolean(tagsInput)}
        aria-label={t('capture.tagsPlaceholder')}
      >
        <span aria-hidden="true" className="text-2xs">{'\uD83C\uDFF7'}</span>
        {!showInput && <span>{t('task.tags')}</span>}
      </ToggleChip>
      {showInput && (
        <div className="relative">
          <input
            ref={inputRef}
            type="text"
            value={tagsInput}
            onChange={(e) => setTagsInput(clampQuickCaptureTagDraftInput(e.target.value))}
            onFocus={() => setFocused(true)}
            onBlur={handleBlur}
            onKeyDown={handleKeyDown}
            placeholder={t('capture.tagsPlaceholder')}
            aria-label={t('capture.tagsPlaceholder')}
            aria-autocomplete="list"
            aria-controls={showDropdown ? tagSuggestionsListboxId : undefined}
            aria-activedescendant={activeSuggestionId}
            aria-expanded={showDropdown}
            role="combobox"
            className="w-24 bg-transparent text-text-primary text-xs outline-hidden placeholder:text-text-muted/60 border-b border-surface-3 focus-visible:border-accent/60 py-0.5 transition-colors"
          />
          {showDropdown && panelPos && createPortal(
            <div
              className={`fixed ${QUICK_CAPTURE_POPOVER_Z_CLASS} ${QUICK_CAPTURE_POPOVER_SHELL_CLASS} py-1`}
              style={{
                top: panelPos.top,
                left: panelPos.left,
                width: panelPos.width,
              }}
              id={tagSuggestionsListboxId}
              role="listbox"
              aria-orientation="vertical"
              onClick={(event) => event.stopPropagation()}
              onKeyDown={(event) => event.stopPropagation()}
            >
              {suggestions.map((tag, idx) => (
                // <button role="option"> is a WAI-ARIA contradiction:
                // listbox children must be plain options with no implicit
                // role conflict. Use a <div role="option"> instead;
                // pointer activation is wired with onClick +
                // onMouseDown(prevent default) so the combobox input keeps
                // focus during selection. Mirrors CommandPalette.tsx.
                // Keyboard activation flows through the combobox
                // input's onKeyDown via aria-activedescendant; the
                // option element only handles pointer activation.
                // eslint-disable-next-line jsx-a11y/click-events-have-key-events
                <div
                  key={tag.display_name}
                  id={`${tagSuggestionsListboxId}-option-${idx}`}
                  role="option"
                  aria-selected={idx === highlightIndex}
                  onMouseDown={(e) => {
                    // Prevent blur from firing before we can handle the click
                    e.preventDefault();
                  }}
                  onClick={() => selectSuggestion(tag)}
                  onMouseEnter={() => setHighlightIndex(idx)}
                  className={`w-full flex items-center gap-2 text-xs px-2.5 py-1.5 text-start transition-colors cursor-pointer ${
                    idx === highlightIndex
                      ? 'bg-accent/10 text-text-primary'
                      : 'text-text-secondary hover:bg-surface-3'
                  }`}
                >
                  {tag.color && (
                    <span
                      className="w-2 h-2 rounded-full shrink-0"
                      style={{ backgroundColor: themedSwatch(tag.color, 'dot') }}
                    />
                  )}
                  <span className="truncate">{tag.display_name}</span>
                </div>
              ))}
            </div>,
            document.body,
          )}
        </div>
      )}
      {tagsInput && (
        <button
          type="button"
          onClick={() => { setTagsInput(''); setExpanded(false); }}
          aria-label={t('common.clear')}
          className="text-text-muted hover:text-text-primary text-xs transition-colors focus-ring-soft rounded-r-control"
        >
          <XIcon className="w-3 h-3" />
        </button>
      )}
    </div>
  );
}
