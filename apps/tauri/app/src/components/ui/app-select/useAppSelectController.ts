import {
  useEffect,
  useId,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ChangeEvent as ReactChangeEvent,
  type FocusEvent as ReactFocusEvent,
  type KeyboardEvent as ReactKeyboardEvent,
  type RefObject,
} from 'react';

import { createBrowserAppSelectRuntimeDeps } from './AppSelect.runtime';
import { findNextEnabledOption } from './navigation';
import {
  type AppSelectProps,
  normalizeSelectValue,
  parseOptions,
  type ParsedOption,
} from './model';
import {
  extractLayoutClasses,
  VARIANT_TRIGGER_CLASSES,
} from './styles';
import {
  resolvePortalDropdownListboxPosition,
} from '../portalDropdown.runtime';

interface ListboxPosition {
  top: number;
  left: number;
  width: number;
  openUpward: boolean;
}

export interface AppSelectController {
  activeIndex: number;
  handleKeyDown: (event: ReactKeyboardEvent<HTMLButtonElement>) => void;
  handleTriggerBlur: (event: ReactFocusEvent<HTMLButtonElement>) => void;
  handleTriggerClick: () => void;
  handleTriggerFocus: (event: ReactFocusEvent<HTMLButtonElement>) => void;
  layoutClassName: string;
  listboxId: string;
  listboxPosition: ListboxPosition | null;
  listboxRef: RefObject<HTMLDivElement | null>;
  open: boolean;
  optionRefs: RefObject<Array<HTMLDivElement | null>>;
  options: ParsedOption[];
  portalTarget: Element | DocumentFragment | null;
  rootRef: RefObject<HTMLDivElement | null>;
  selectOption: (option: ParsedOption) => void;
  selectedOption: ParsedOption | undefined;
  selectedValue: string;
  triggerRef: RefObject<HTMLButtonElement | null>;
  triggerVariantClasses: string;
  viewportHeight: number | null;
}

export function useAppSelectController({
  variant = 'default',
  className,
  children,
  value,
  defaultValue,
  disabled = false,
  onChange,
  onBlur,
  onFocus,
  autoFocus,
  name,
}: AppSelectProps): AppSelectController {
  const runtimeDeps = useMemo(() => createBrowserAppSelectRuntimeDeps(), []);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const listboxRef = useRef<HTMLDivElement>(null);
  const optionRefs = useRef<Array<HTMLDivElement | null>>([]);
  const listboxId = useId();
  const [listboxPosition, setListboxPosition] = useState<ListboxPosition | null>(null);
  const [viewportHeight, setViewportHeight] = useState<number | null>(null);
  const options = useMemo(() => parseOptions(children), [children]);

  // Trim stale refs when option count shrinks
  useEffect(() => {
    optionRefs.current = optionRefs.current.slice(0, options.length);
  }, [options.length]);
  const layoutClassName = extractLayoutClasses(className);
  const triggerVariantClasses = VARIANT_TRIGGER_CLASSES[variant] ?? VARIANT_TRIGGER_CLASSES.default;
  const isControlled = value !== undefined;
  const hasExplicitDefaultValue = defaultValue !== undefined;
  const firstEnabled = options.find((option) => !option.disabled)?.value ?? options[0]?.value ?? '';
  const [internalValue, setInternalValue] = useState<string>(() => {
    const initial = normalizeSelectValue(defaultValue);
    return hasExplicitDefaultValue ? initial : firstEnabled;
  });
  const selectedValue = isControlled ? normalizeSelectValue(value) : internalValue;
  const selectedOption = options.find((option) => option.value === selectedValue) ?? options[0];
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);

  useEffect(() => {
    if (!isControlled && options.length > 0 && !options.some((option) => option.value === internalValue)) {
      setInternalValue(firstEnabled);
    }
  }, [firstEnabled, internalValue, isControlled, options]);

  useEffect(() => {
    if (autoFocus) {
      triggerRef.current?.focus();
    }
  }, [autoFocus]);

  useEffect(() => {
    if (!open) return;
    const selectedIndex = options.findIndex((option) => option.value === selectedValue);
    if (selectedIndex >= 0 && !options[selectedIndex]!.disabled) {
      setActiveIndex(selectedIndex);
      return;
    }
    setActiveIndex(options.findIndex((option) => !option.disabled));
  }, [open, options, selectedValue]);

  useEffect(() => {
    if (!open || activeIndex < 0) return;
    const target = optionRefs.current[activeIndex];
    target?.scrollIntoView({ block: 'nearest' });
  }, [activeIndex, open]);

  // Compute fixed position for the portal-rendered listbox
  useLayoutEffect(() => {
    if (!open || !triggerRef.current) {
      setListboxPosition(null);
      setViewportHeight(null);
      return;
    }
    const viewport = runtimeDeps.readViewport();
    if (!viewport) {
      setListboxPosition(null);
      setViewportHeight(null);
      return;
    }
    const rect = triggerRef.current.getBoundingClientRect();
    setListboxPosition(
      resolvePortalDropdownListboxPosition(rect, viewport.width, viewport.height),
    );
    setViewportHeight(viewport.height);
  }, [open, runtimeDeps]);

  // Click-outside and scroll handlers to close the portal dropdown
  useEffect(() => {
    if (!open) return;
    return runtimeDeps.startDismissRuntime({
      getTrigger: () => rootRef.current,
      getPanel: () => listboxRef.current,
      onDismiss: () => setOpen(false),
    });
  }, [open, runtimeDeps]);

  const emitChange = (nextValue: string) => {
    if (!isControlled) {
      setInternalValue(nextValue);
    }
    if (!onChange) return;
    const target = { value: nextValue, name: name ?? '' } as EventTarget & HTMLSelectElement;
    onChange({
      target,
      currentTarget: target,
    } as ReactChangeEvent<HTMLSelectElement>);
  };

  const selectOption = (option: ParsedOption) => {
    if (option.disabled) return;
    emitChange(option.value);
    setOpen(false);
  };

  const handleKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>) => {
    if (disabled || options.length === 0) return;

    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const direction: 1 | -1 = event.key === 'ArrowDown' ? 1 : -1;
      if (!open) {
        setOpen(true);
      }
      const start =
        activeIndex >= 0
          ? activeIndex
          : Math.max(
              options.findIndex((option) => option.value === selectedValue),
              0,
            );
      setActiveIndex(findNextEnabledOption(options, start, direction));
      return;
    }

    if (event.key === 'Home') {
      event.preventDefault();
      setOpen(true);
      setActiveIndex(options.findIndex((option) => !option.disabled));
      return;
    }

    if (event.key === 'End') {
      event.preventDefault();
      setOpen(true);
      for (let idx = options.length - 1; idx >= 0; idx -= 1) {
        if (!options[idx]!.disabled) {
          setActiveIndex(idx);
          break;
        }
      }
      return;
    }

    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      if (!open) {
        setOpen(true);
        return;
      }
      const option = options[activeIndex];
      if (option && !option.disabled) {
        selectOption(option);
      }
      return;
    }

    if (event.key === 'Escape' && open) {
      event.preventDefault();
      event.stopPropagation();
      setOpen(false);
    }
  };

  const handleTriggerFocus = (event: ReactFocusEvent<HTMLButtonElement>) => {
    // AppSelectProps now types `onFocus` /
    // `onBlur` with `ReactFocusEvent<HTMLElement>` (model.ts), so
    // `HTMLButtonElement` flows through without the previous
    // double-cast. Caller code that treats focus/blur as opaque
    // visibility signals is unaffected; caller code that read
    // `event.nativeEvent` would have been getting the button shape
    // at runtime anyway, so the type now matches reality.
    onFocus?.(event);
  };

  const handleTriggerBlur = (event: ReactFocusEvent<HTMLButtonElement>) => {
    if (runtimeDeps.containsTarget(rootRef.current, event.relatedTarget)) {
      return;
    }
    setOpen(false);
    onBlur?.(event);
  };

  const handleTriggerClick = () => {
    setOpen((prev) => !prev);
  };

  return {
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
    portalTarget: runtimeDeps.readPortalTarget(),
    rootRef,
    selectOption,
    selectedOption,
    selectedValue,
    triggerRef,
    triggerVariantClasses,
    viewportHeight,
  };
}
