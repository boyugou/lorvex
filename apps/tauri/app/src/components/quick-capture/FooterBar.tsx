import { useId } from 'react';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { decodeListSelectionValue, encodeListSelectionValue } from '@/lib/listSelection';
import { AppSelect } from '../ui/AppSelect';
import { Tooltip } from '../ui/Tooltip';
import { useReducedMotion } from '@/lib/reducedMotion';
import type { useI18n } from '@/lib/i18n';

/**
 * Inline 12px spinner sibling to the submit label. Mirrors the
 * `<SubmitButton>` primitive's spinner, but FooterBar uses
 * `aria-disabled` (not the native `disabled` attribute) so SR users
 * can still tab to the button to learn why it's dimmed. That
 * means we render the spinner alongside the original label-swap
 * pattern rather than swapping the entire button to `SubmitButton`.
 */
function FooterSpinner() {
  const reduced = useReducedMotion();
  return (
    <svg aria-hidden="true" width="12" height="12" viewBox="0 0 24 24" fill="none" className={reduced ? '' : 'animate-spin'}>
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.35" strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

interface FooterBarProps {
  lists: ListWithCount[];
  selectedListId: string | null;
  setSelectedListId: (id: string | null) => void;
  listRequiredHint: string | null;
  activeDateLabel: string | null;
  canSubmit: boolean;
  submitting: boolean;
  onSubmit: () => void;
  onSubmitAndContinue: () => void;
  isMobile: boolean;
  t: ReturnType<typeof useI18n>['t'];
}

export default function FooterBar({
  lists,
  selectedListId,
  setSelectedListId,
  listRequiredHint,
  activeDateLabel,
  canSubmit,
  submitting,
  onSubmit,
  onSubmitAndContinue,
  isMobile,
  t,
}: FooterBarProps) {
  // Wire `aria-invalid` + `aria-errormessage` on the list picker
  // when the "list required" hint fires, so the hint text is bound
  // to the `<select>` and screen readers announce it.
  const listSelectId = useId();
  const listErrorId = `${listSelectId}-error`;
  const listInvalid = Boolean(listRequiredHint);
  const saveAndAddAnotherLabel = t('capture.saveAndAddAnother');
  return (
    <div
      className="flex flex-col gap-2 px-4 py-3 border-t border-surface-3"
      // on mobile, add the soft-keyboard inset on top of
      // the safe-area padding so the submit button stays visible above
      // the keyboard. `--kb-inset` is installed by
      // `useVisualViewportInset` in the mobile shell.
      style={isMobile
        ? { paddingBottom: 'calc(max(1.25rem, env(safe-area-inset-bottom, 1.25rem)) + var(--kb-inset, 0px))' }
        : undefined}
    >
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-text-muted text-xs">{t('common.to')}</span>
        <div className="min-w-0 flex-[1_1_12rem] max-w-full">
          <AppSelect
            variant="inline"
            popoverLayer="modalPopover"
            id={listSelectId}
            aria-label={t('allTasks.pickList')}
            aria-invalid={listInvalid}
            aria-errormessage={listInvalid ? listErrorId : undefined}
            value={selectedListId ? encodeListSelectionValue(selectedListId) : ''}
            onChange={e => {
              if (!e.target.value) {
                setSelectedListId(null);
                return;
              }
              setSelectedListId(decodeListSelectionValue(e.target.value));
            }}
            className="w-full min-w-0"
          >
            <option value="">{t('allTasks.pickList')}</option>
            {lists.map(list => (
              <option key={list.id} value={encodeListSelectionValue(list.id)}>
                {list.icon ? `${list.icon} ` : ''}{list.name}
              </option>
            ))}
          </AppSelect>
        </div>
        {activeDateLabel && (
          <span className="min-w-0 max-w-full flex-[1_1_8rem] truncate text-xs text-accent/80 sm:flex-none">
            {'\uD83D\uDCC5'} {activeDateLabel}
          </span>
        )}
        {/* native `disabled` removes the button
            from the focus order, so SR users can't tab to it to learn
            *why* it's disabled. Using `aria-disabled` keeps it
            focusable + announced as "dimmed", and `aria-describedby`
            points at the existing listRequiredHint <p role="alert">
            when present so the SR reads the hint as supplementary
            description. We intercept the click ourselves to preserve
            the no-op behaviour the native attribute used to provide. */}
        <div className={`flex min-w-0 items-center gap-1.5 ${isMobile ? 'w-full justify-end' : 'ms-auto justify-end'}`}>
          <button
            type="button"
            onClick={canSubmit ? onSubmit : undefined}
            aria-disabled={!canSubmit}
            aria-busy={submitting || undefined}
            aria-describedby={listInvalid ? listErrorId : undefined}
            className={`inline-flex min-w-fit items-center justify-center gap-1.5 px-3 py-1.5 rounded-r-control bg-accent hover:bg-accent-hover text-on-accent text-sm active:scale-[0.97] shadow-[var(--shadow-tooltip)] hover:shadow transition-[color,background-color,box-shadow,transform] duration-150 focus-ring-strong ${canSubmit ? '' : 'opacity-40 cursor-not-allowed'}`}
          >
            {submitting && <FooterSpinner />}
            <span>{submitting ? t('capture.submitting') : t('capture.addTask')}</span>
          </button>
          {!isMobile && (
            <Tooltip label={saveAndAddAnotherLabel}>
              <button
                type="button"
                onClick={canSubmit ? onSubmitAndContinue : undefined}
                aria-label={saveAndAddAnotherLabel}
                aria-keyshortcuts="Shift+Meta+Enter Shift+Control+Enter"
                aria-disabled={!canSubmit}
                aria-describedby={listInvalid ? listErrorId : undefined}
                className={`text-text-muted hover:text-text-secondary text-3xs shrink-0 transition-colors focus-ring-soft rounded-r-control px-1.5 py-1 hover:bg-surface-3/50 ${canSubmit ? '' : 'opacity-40 cursor-not-allowed'}`}
              >
                <span aria-hidden="true">&#8679;&#8984;&#9166;</span>
              </button>
            </Tooltip>
          )}
        </div>
      </div>
      {listRequiredHint && (
        <p id={listErrorId} role="alert" className="text-xs text-warning">
          {listRequiredHint}
        </p>
      )}
    </div>
  );
}
