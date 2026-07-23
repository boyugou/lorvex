import type { ListWithCount } from '@/lib/ipc/tasks/models';
import type { QuickCaptureInitialData } from '../app-shell/main-window/types';
import { useQuickCaptureForm } from './quick-capture/useQuickCaptureForm';
import TitleInput from './quick-capture/TitleInput';
import CompactToolbar from './quick-capture/CompactToolbar';
import FooterBar from './quick-capture/FooterBar';
import { Modal } from './ui/Modal';
import { Button } from './ui/Button';
import { XIcon } from './ui/icons';
import { Tooltip } from './ui/Tooltip';

interface Props {
  lists: ListWithCount[];
  onClose: () => void;
  isMobile?: boolean;
  initialData?: QuickCaptureInitialData | null;
  sessionId?: number | null;
  /** invoked from the failure-toast Retry action. */
  onReopenForRetry?: ((draft: QuickCaptureInitialData) => void) | undefined;
}

export default function QuickCapture({
  lists,
  onClose,
  isMobile = false,
  initialData,
  onReopenForRetry,
  sessionId,
}: Props) {
  const form = useQuickCaptureForm({
    lists,
    onClose,
    initialData: initialData ?? undefined,
    onReopenForRetry,
    sessionId,
  });

  return (
    <Modal
      open
      onClose={() => { void form.requestClose(); }}
      size="lg"
      zIndex="z-[var(--z-modal)]"
      align={isMobile ? 'items-end justify-stretch' : 'items-start justify-center pt-[20vh]'}
      panelClassName={isMobile ? '!max-w-none !rounded-t-[var(--radius-r-modal)] !rounded-b-none' : ''}
      ariaLabel={form.t('capture.placeholder')}
      // hand the title input ref directly to Modal so
      // it focuses the right child on mount. Replaces the prior
      // pattern (autoFocus={false} + useEffect inputRef.current?.focus()),
      // which had to special-case stable ref identity to dodge the
      // regression where re-creating the ref mid-open snatched
      // focus back from a chip the user was actively editing. Modal
      // resolves the ref at mount time and never re-focuses, so the
      // identity churn no longer matters.
      focusTarget={form.inputRef}
    >
      {isMobile ? (
        <button
          type="button"
          onClick={() => { void form.requestClose(); }}
          aria-label={form.t('common.close')}
          className="w-full pt-2 pb-1 flex justify-center hover:bg-surface-3/50 active:bg-surface-3 transition-colors focus-ring-soft rounded-t-[var(--radius-r-panel)]"
        >
          <div className="h-1.5 w-10 rounded-full bg-surface-3" />
        </button>
      ) : (
        <div className="flex justify-end px-3 pt-2.5 pb-0">
          <Tooltip label={`${form.t('common.close')} (Esc)`}>
            {/* canonical icon-button primitive. Ghost variant
                + size='icon' delivers the 28×28 dismiss-X recipe with
                the documented `focus-ring-soft` policy. */}
            <Button
              variant="ghost"
              size="icon"
              onClick={() => { void form.requestClose(); }}
              aria-label={form.t('common.close')}
            >
              <XIcon className="w-4.5 h-4.5" />
            </Button>
          </Tooltip>
        </div>
      )}

      <TitleInput
        title={form.title}
        setTitle={form.setTitle}
        body={form.body}
        setBody={form.setBody}
        showBody={form.showBody}
        setShowBody={form.setShowBody}
        isComposing={form.isComposing}
        setIsComposing={form.setIsComposing}
        onSubmit={form.handleSubmit}
        onSubmitAndContinue={form.handleSubmitAndContinue}
        canSubmit={form.canSubmit}
        inputRef={form.inputRef}
        isMobile={isMobile}
        t={form.t}
        tagsInput={form.tagsInput}
        setTagsInput={form.setTagsInput}
      />

      {/* Single compact toolbar — replaces separate date/priority/duration/tags rows */}
      <CompactToolbar
        dateOption={form.dateOption}
        customDate={form.customDate}
        setCustomDate={form.setCustomDate}
        setDateOption={form.setDateOption}
        toggleDateOption={form.toggleDateOption}
        clearDate={form.clearDate}
        activeNlDate={form.activeNlDate}
        clearNlDate={form.clearNlDate}
        priority={form.priority}
        togglePriority={form.togglePriority}
        clearPriority={form.clearPriority}
        estimatedMinutes={form.estimatedMinutes}
        setEstimatedMinutes={form.setEstimatedMinutes}
        toggleDuration={form.toggleDuration}
        clearDuration={form.clearDuration}
        tagsInput={form.tagsInput}
        setTagsInput={form.setTagsInput}
        t={form.t}
      />

      <FooterBar
        lists={lists}
        selectedListId={form.selectedListId}
        setSelectedListId={form.setSelectedListId}
        listRequiredHint={form.listRequiredHint}
        activeDateLabel={form.activeDateLabel}
        canSubmit={form.canSubmit}
        submitting={form.submitting}
        onSubmit={form.handleSubmit}
        onSubmitAndContinue={form.handleSubmitAndContinue}
        isMobile={isMobile}
        t={form.t}
      />
    </Modal>
  );
}
