import {
  Children,
  isValidElement,
  type FocusEvent as ReactFocusEvent,
  type ReactNode,
  type SelectHTMLAttributes,
} from 'react';

import { VARIANT_TRIGGER_CLASSES } from './styles';
import type { PopoverLayer } from '../popoverLayer';

type AppSelectVariant = keyof typeof VARIANT_TRIGGER_CLASSES;

/// AppSelect renders as a button + popover, not a native
/// `<select>`. The controller emits
/// `ReactFocusEvent<HTMLButtonElement>` from the trigger, so the
/// inherited `onFocus` / `onBlur` types from
/// `SelectHTMLAttributes<HTMLSelectElement>` are wrong: a caller
/// consuming `event.target` or `event.nativeEvent` (which carry
/// the actual element kind at runtime) would get the button shape
/// rather than the select shape the type promised.
///
/// Override the two events to a generic `HTMLElement` target — the
/// concrete element type is irrelevant to every existing consumer
/// (they treat focus/blur as opaque visibility signals), and the
/// generic type lets the controller emit button events without a
/// lying cast.
export interface AppSelectProps
  extends Omit<SelectHTMLAttributes<HTMLSelectElement>, 'onFocus' | 'onBlur'> {
  variant?: AppSelectVariant;
  popoverLayer?: PopoverLayer;
  onFocus?: (event: ReactFocusEvent<HTMLElement>) => void;
  onBlur?: (event: ReactFocusEvent<HTMLElement>) => void;
}

export interface ParsedOption {
  key: string;
  value: string;
  label: ReactNode;
  disabled: boolean;
}

interface AppSelectOptionProps {
  children?: ReactNode;
  disabled?: unknown;
  value?: unknown;
}

export function normalizeSelectValue(value: unknown): string {
  if (value == null) return '';
  if (Array.isArray(value)) {
    return value.length > 0 ? String(value[0]) : '';
  }
  return String(value);
}

export function parseOptions(children: ReactNode): ParsedOption[] {
  const options: ParsedOption[] = [];
  Children.forEach(children, (child, index) => {
    if (!isValidElement<AppSelectOptionProps>(child) || child.type !== 'option') {
      return;
    }
    const { props } = child;
    const value = normalizeSelectValue(props.value ?? props.children);
    options.push({
      key: child.key?.toString() ?? `${value}-${index}`,
      value,
      label: props.children,
      disabled: Boolean(props.disabled),
    });
  });
  return options;
}
