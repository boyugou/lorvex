import type { ReactNode } from 'react';

import type { DatePickerController } from './DatePicker.controller';
import { ModalShell } from './overlay';

interface DatePickerMobileSheetProps {
  controller: DatePickerController;
  children: ReactNode;
}

export function DatePickerMobileSheet({ controller, children }: DatePickerMobileSheetProps) {
  const {
    onClose,
    layerClasses,
    pickDateLabel,
    handleKeyDown,
    panelRef,
  } = controller;

  return (
    <ModalShell
      open
      onClose={onClose}
      zIndex={layerClasses.root}
      align="items-end justify-center"
      backdropClassName="bg-[var(--color-overlay)] animate-[fade-in_0.12s_ease-out]"
      panelClassName="w-full bg-surface-1 border-t border-surface-3 rounded-t-[var(--radius-r-panel)] animate-[slide-in-up_0.2s_ease-out] max-h-[90vh] max-h-[90dvh] overflow-y-auto"
      ariaLabel={pickDateLabel}
      onPanelKeyDown={handleKeyDown}
      panelRef={panelRef}
    >
      <div
        className="px-4 pt-2 pb-4"
        style={{ paddingBottom: 'max(1rem, env(safe-area-inset-bottom, 0px))' }}
      >
        <div className="w-10 h-1 rounded-full bg-surface-3 mx-auto mb-3" />
        {children}
      </div>
    </ModalShell>
  );
}
