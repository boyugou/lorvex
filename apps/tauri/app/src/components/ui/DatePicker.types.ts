import type React from 'react';

import type { PopoverLayer } from './popoverLayer';

export interface DatePickerProps {
  value: string | null;
  onChange: (date: string | null) => void;
  onClose: () => void;
  anchorRef?: React.RefObject<HTMLElement | null>;
  showQuickChips?: boolean;
  showClearButton?: boolean | undefined;
  minDate?: string | undefined;
  popoverLayer?: PopoverLayer;
}
