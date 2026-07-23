import type { LocaleTextDirection } from '@/locales/registry';
import type { TooltipSide } from '../ui/Tooltip.runtime';

export function navItemTooltipSideForDirection(textDirection: LocaleTextDirection): TooltipSide {
  return textDirection === 'rtl' ? 'left' : 'right';
}
