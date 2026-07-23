import type { MouseEvent, ReactNode } from 'react';
import { createPortal } from 'react-dom';

import type { DatePickerController } from './DatePicker.controller';

interface DatePickerDesktopPopoverProps {
  controller: DatePickerController;
  children: ReactNode;
}

export function DatePickerDesktopPopover({ controller, children }: DatePickerDesktopPopoverProps) {
  const {
    layerClasses,
    handleBackdropClick,
    panelRef,
    pickDateLabel,
    handleKeyDown,
    position,
  } = controller;

  const handlePortalClick = (event: MouseEvent<HTMLDivElement>) => {
    event.stopPropagation();
    handleBackdropClick(event);
  };

  const panel = (
    <div
      className={`fixed inset-0 ${layerClasses.backdrop}`}
      onClick={handlePortalClick}
      role="presentation"
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-label={pickDateLabel}
        onKeyDown={handleKeyDown}
        tabIndex={-1}
        className={`absolute ${layerClasses.panel} bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] w-[var(--popover-w-md)] p-3 max-h-[calc(100vh-24px)] max-h-[calc(100dvh-24px)] overflow-y-auto`}
        style={{ top: position.top, left: position.left }}
      >
        {children}
      </div>
    </div>
  );

  return createPortal(panel, document.body);
}
