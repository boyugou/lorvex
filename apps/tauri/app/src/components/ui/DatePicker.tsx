import { memo } from 'react';

import { useDatePickerController } from './DatePicker.controller';
import { DatePickerContent } from './DatePickerContent';
import { DatePickerDesktopPopover } from './DatePickerDesktopPopover';
import { DatePickerMobileSheet } from './DatePickerMobileSheet';
import type { DatePickerProps } from './DatePicker.types';

export const DatePicker = memo(function DatePicker(props: DatePickerProps) {
  const controller = useDatePickerController(props);
  const content = <DatePickerContent controller={controller} />;

  if (controller.isMobile) {
    return (
      <DatePickerMobileSheet controller={controller}>
        {content}
      </DatePickerMobileSheet>
    );
  }

  return (
    <DatePickerDesktopPopover controller={controller}>
      {content}
    </DatePickerDesktopPopover>
  );
});
