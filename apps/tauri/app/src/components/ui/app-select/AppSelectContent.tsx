import type { CSSProperties } from 'react';
import { createPortal } from 'react-dom';
import { CheckIcon } from '../icons';

import type { AppSelectProps } from './model';
import {
  BASE_TRIGGER_CLASSES,
  joinClasses,
  LISTBOX_CLASSES,
  OPEN_TRIGGER_CLASSES,
} from './styles';
import type { AppSelectController } from './useAppSelectController';
import { getPopoverLayerClasses } from '../popoverLayer';

interface AppSelectContentProps extends Pick<
  AppSelectProps,
  | 'aria-describedby'
  | 'aria-errormessage'
  | 'aria-invalid'
  | 'aria-label'
  | 'aria-labelledby'
  | 'className'
  | 'disabled'
  | 'id'
  | 'name'
  | 'popoverLayer'
  | 'required'
  | 'style'
  | 'tabIndex'
  | 'title'
> {
  controller: AppSelectController;
}

export function AppSelectContent({
  controller,
  className,
  disabled = false,
  id,
  name,
  required,
  style,
  tabIndex,
  title,
  popoverLayer = 'popover',
  'aria-label': ariaLabel,
  'aria-labelledby': ariaLabelledBy,
  'aria-describedby': ariaDescribedBy,
  'aria-invalid': ariaInvalid,
  'aria-errormessage': ariaErrorMessage,
}: AppSelectContentProps) {
  const {
    activeIndex,
    handleKeyDown,
    handleTriggerBlur,
    handleTriggerClick,
    handleTriggerFocus,
    layoutClassName,
    listboxId,
    listboxPosition,
    listboxRef,
    open,
    optionRefs,
    options,
    portalTarget,
    rootRef,
    selectOption,
    selectedOption,
    selectedValue,
    triggerRef,
    triggerVariantClasses,
    viewportHeight,
  } = controller;
  const layerClasses = getPopoverLayerClasses(popoverLayer);

  return (
    <div ref={rootRef} className={joinClasses('relative inline-block', layoutClassName, open && 'z-[var(--z-overlay)]')}>
      <button
        ref={triggerRef}
        type="button"
        id={id}
        disabled={disabled}
        title={title}
        tabIndex={tabIndex}
        aria-label={ariaLabel}
        aria-labelledby={ariaLabelledBy}
        aria-describedby={ariaDescribedBy}
        // AppSelect is a combobox widget, not a native
        // <select>. Forward `aria-invalid` + `aria-errormessage` so
        // validation state is announced by screen readers and picked
        // up by the `.validated-input[aria-invalid=true]` CSS rule.
        aria-invalid={ariaInvalid}
        aria-errormessage={ariaErrorMessage}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listboxId}
        aria-activedescendant={open && activeIndex >= 0 ? `${listboxId}-option-${activeIndex}` : undefined}
        aria-disabled={disabled}
        data-state={open ? 'open' : 'closed'}
        // opt-in marker for ember/midnight theme form-control
        // radius/border treatment. AppSelect is the canonical select
        // primitive and gets the same treatment as Input/Button.
        data-theme-form-control="true"
        role="combobox"
        className={joinClasses(
          'validated-input',
          BASE_TRIGGER_CLASSES,
          triggerVariantClasses,
          className,
          open && OPEN_TRIGGER_CLASSES,
        )}
        style={style as CSSProperties | undefined}
        onClick={handleTriggerClick}
        onKeyDown={handleKeyDown}
        onFocus={handleTriggerFocus}
        onBlur={handleTriggerBlur}
      >
        <span className={joinClasses('truncate text-start', selectedOption?.disabled && 'text-text-muted')}>
          {selectedOption?.label ?? ''}
        </span>
        <svg
          aria-hidden="true"
          className={joinClasses('h-3.5 w-3.5 text-text-muted transition-transform', open && 'rotate-180')}
          viewBox="0 0 20 20"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M5 7l5 6 5-6" />
        </svg>
      </button>

      {name && <input type="hidden" name={name} value={selectedValue} required={required} />}

      {open && options.length > 0 && listboxPosition && portalTarget && createPortal(
        <div
          ref={listboxRef}
          id={listboxId}
          role="listbox"
          aria-orientation="vertical"
          className={joinClasses(LISTBOX_CLASSES, 'fixed', layerClasses.panel)}
          style={{
            top: listboxPosition.openUpward ? undefined : listboxPosition.top,
            bottom: listboxPosition.openUpward && viewportHeight !== null
              ? viewportHeight - listboxPosition.top
              : undefined,
            // The resolver returns physical viewport coordinates for the
            // fixed-position portal; keep the render side physical too so RTL
            // directionality does not mirror the offset.
            left: listboxPosition.left,
            width: Math.max(listboxPosition.width, 120),
          }}
        >
          {options.map((option, index) => {
            const isSelected = option.value === selectedValue;
            const isActive = index === activeIndex;
            // <button role="option"> is a WAI-ARIA contradiction —
            // listbox children must be plain options with no implicit
            // role conflict. JAWS / NVDA narrate the native button role
            // *and* the option role, leading to double announcements
            // ("button, option, list item"). Use a <div role="option">
            // instead; keyboard activation flows through the trigger's
            // onKeyDown via aria-activedescendant + handleKeyDown, and
            // pointer activation is wired with onClick + onMouseDown
            // (prevent default) so the trigger keeps focus during
            // selection. Mirrors CommandPalette.tsx.
            return (
              <div
                key={option.key}
                id={`${listboxId}-option-${index}`}
                role="option"
                aria-selected={isSelected}
                aria-disabled={option.disabled}
                ref={(node) => {
                  optionRefs.current[index] = node;
                }}
                className={joinClasses(
                  'w-full text-start px-2 py-2 rounded-r-control text-sm leading-normal transition-colors flex items-center gap-2',
                  option.disabled ? 'opacity-40 cursor-not-allowed' : 'cursor-pointer hover:bg-surface-3',
                  isSelected && 'text-accent',
                  isActive && !option.disabled && 'bg-surface-3',
                )}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => selectOption(option)}
                onKeyDown={(event) => {
                  // The trigger owns keyboard navigation via
                  // aria-activedescendant; this local Enter/Space
                  // handler keeps activation working when focus
                  // somehow lands on an option directly (a11y
                  // baseline — any clickable element should also
                  // respond to keyboard activation).
                  if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    selectOption(option);
                  }
                }}
              >
                <span className="truncate">{option.label}</span>
                {isSelected && !option.disabled && (
                  <CheckIcon aria-hidden="true" className="text-accent w-3 h-3 ms-2 shrink-0" />
                )}
              </div>
            );
          })}
        </div>,
        portalTarget,
      )}
    </div>
  );
}
