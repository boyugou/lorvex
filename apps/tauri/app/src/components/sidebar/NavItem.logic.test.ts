import { describe, expect, it } from 'vitest';
import { computeTooltipPosition } from '../ui/Tooltip.runtime';
import { navItemTooltipSideForDirection } from './NavItem.logic';

describe('navItemTooltipSideForDirection', () => {
  it('places sidebar tooltips on inline-end for both LTR and RTL layouts', () => {
    expect(navItemTooltipSideForDirection('ltr')).toBe('right');
    expect(navItemTooltipSideForDirection('rtl')).toBe('left');
  });

  it('feeds the tooltip runtime a physical side that avoids RTL sidebar overlap', () => {
    const trigger = { top: 120, left: 920, width: 72, height: 32 };
    const tooltip = { width: 128, height: 40 };
    const viewport = { width: 1024, height: 768 };

    const position = computeTooltipPosition(
      trigger,
      tooltip,
      viewport,
      navItemTooltipSideForDirection('rtl'),
      8,
    );

    expect(position.x).toBeLessThan(trigger.left);
    expect(position.y).toBe(116);
  });
});
