import { describe, expect, it } from 'vitest';

import {
  formatSliderPercentLabel,
  resolveLogicalSliderFillStyle,
  resolveLogicalSliderThumbStyle,
  resolveSliderFillPercent,
  resolveSliderTrackBackground,
} from './sliderGeometry.logic';

describe('resolveSliderFillPercent', () => {
  it('normalizes values to a clamped 0-100 percentage', () => {
    expect(resolveSliderFillPercent({ value: 65, min: 30, max: 100 })).toBe(50);
    expect(resolveSliderFillPercent({ value: 10, min: 30, max: 100 })).toBe(0);
    expect(resolveSliderFillPercent({ value: 130, min: 30, max: 100 })).toBe(100);
    expect(resolveSliderFillPercent({ value: 1, min: 1, max: 1 })).toBe(0);
  });
});

describe('resolveSliderTrackBackground', () => {
  it('uses physical LTR and RTL gradient directions that match native range direction', () => {
    expect(resolveSliderTrackBackground({ fillPercent: 40, textDirection: 'ltr' })).toContain('linear-gradient(to right');
    expect(resolveSliderTrackBackground({ fillPercent: 40, textDirection: 'rtl' })).toContain('linear-gradient(to left');
  });

  it('clamps gradient stops before composing the CSS string', () => {
    expect(resolveSliderTrackBackground({ fillPercent: 140, textDirection: 'ltr' })).toContain('100%');
    expect(resolveSliderTrackBackground({ fillPercent: -10, textDirection: 'rtl' })).toContain('0%');
  });
});

describe('logical slider styles', () => {
  it('anchors fill and thumb to inline-start so RTL mirrors without physical left offsets', () => {
    expect(resolveLogicalSliderFillStyle(42)).toEqual({
      insetInlineStart: '0%',
      inlineSize: '42%',
    });
    expect(resolveLogicalSliderThumbStyle({ fillPercent: 42, thumbRadiusPx: 6 })).toEqual({
      insetInlineStart: 'calc(42% - 6px)',
    });
  });
});

describe('formatSliderPercentLabel', () => {
  it('uses Intl percent formatting for the active locale', () => {
    expect(formatSliderPercentLabel(72, 'en')).toBe('72%');

    const formattedRtlPercent = formatSliderPercentLabel(72, 'fa');
    expect(formattedRtlPercent).not.toBe('72%');
    expect(formattedRtlPercent).toContain('۷۲');
    expect(formattedRtlPercent).toContain('٪');
  });
});
