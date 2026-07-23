interface DatePickerDesktopPosition {
  top: number;
  left: number;
}

interface DatePickerAnchorRect {
  top: number;
  left: number;
  bottom: number;
}

const DESKTOP_PANEL_WIDTH_PX = 280;
const DESKTOP_PANEL_HEIGHT_PX = 340;
const DESKTOP_GUTTER_PX = 12;
const DESKTOP_ANCHOR_GAP_PX = 4;
const OFFSCREEN_POSITION = -9999;

export function resolveDatePickerDesktopPosition({
  isMobile,
  anchorRect,
  viewportWidth,
  viewportHeight,
  panelWidth = DESKTOP_PANEL_WIDTH_PX,
  panelHeight = DESKTOP_PANEL_HEIGHT_PX,
  gutter = DESKTOP_GUTTER_PX,
  anchorGap = DESKTOP_ANCHOR_GAP_PX,
}: {
  isMobile: boolean;
  anchorRect: DatePickerAnchorRect | null;
  viewportWidth: number;
  viewportHeight: number;
  panelWidth?: number;
  panelHeight?: number;
  gutter?: number;
  anchorGap?: number;
}): DatePickerDesktopPosition {
  if (isMobile) return { top: 0, left: 0 };
  if (!anchorRect) return { top: OFFSCREEN_POSITION, left: OFFSCREEN_POSITION };

  const spaceBelow = viewportHeight - anchorRect.bottom - gutter;
  const spaceAbove = anchorRect.top - gutter;
  const top = spaceBelow >= panelHeight
    ? anchorRect.bottom + anchorGap
    : spaceAbove >= panelHeight
      ? anchorRect.top - panelHeight - anchorGap
      : Math.max(gutter, viewportHeight - panelHeight - gutter);

  const maxLeft = Math.max(gutter, viewportWidth - panelWidth - gutter);

  return {
    top: Math.max(gutter, top),
    left: Math.min(Math.max(anchorRect.left, gutter), maxLeft),
  };
}
