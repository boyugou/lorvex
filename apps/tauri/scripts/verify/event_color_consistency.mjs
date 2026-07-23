#!/usr/bin/env node
/**
 * Guard against hand-rolled `event.color` references in JSX style props
 * creeping back into the frontend.
 *
 * The canonical helpers are `eventColorStyles({...}, intensity)` and
 * `eventDotColor(color)` in `app/src/lib/colorUtils.ts` (#3664, #3679).
 * Routing every event-surface color through the helpers keeps theme
 * retunes in lockstep across calendar, today-view, popover, and
 * upcoming surfaces — a hand-rolled `event.color || 'var(--color-warning)'`
 * fallback drifts the moment the warning hue changes.
 *
 * Forbidden patterns:
 *
 *   1. `eventColorInStyleProp` — any of:
 *        - `backgroundColor: event.color ...`
 *        - `borderLeft: ... event.color ...`
 *        - `borderColor: event.color ...`
 *        - `color: event.color ...`
 *      inside a JSX `style={{ ... }}` prop. The exemption list below
 *      carries the helpers themselves and any test fixtures.
 *
 * Walk/match/report machinery is delegated to the shared
 * `_forbidden_pattern.mjs` helper (#3625).
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runForbiddenPatternGate } from './_forbidden_pattern.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

runForbiddenPatternGate({
  gateId: 'event_color_consistency',
  scanRoot: path.join(repoRoot, 'app', 'src'),
  repoRoot,
  okMessage:
    '[event_color_consistency] OK — every event.color reference in JSX style props routes through the eventColorStyles / eventDotColor helpers.',
  patterns: [
    {
      id: 'eventColorInStyleProp',
      label: 'raw event.color in a JSX style prop',
      // Match a CSS property whose value references `event.color`
      // directly. The leading capture intentionally requires a
      // CSS-property-style prefix so unrelated `event.color` mentions
      // (e.g. comments, prop drilling) do not trigger.
      // Match a CSS-property assignment whose value contains a bare
      // `event.color` token NOT wrapped in an eventColorStyles(...) /
      // eventDotColor(...) helper call. The negative lookbehind on the
      // helper names is approximate — we walk back at most ~30 chars
      // (covers the helpers + opening paren + a few argument chars).
      // A `??` operator inside the helper call is fine since that
      // text appears AFTER the helper name in the lookbehind window.
      pattern: /(?:backgroundColor|borderLeft|borderColor|borderRight|borderTop|borderBottom|color|outlineColor|fill|stroke)\s*:\s*[^,}\n]*?(?<!eventColorStyles\(|eventDotColor\(|eventColorStyles\([^)]{0,30}|eventDotColor\([^)]{0,30})\bevent\.color\b/,
      suggestion:
        'Route through eventColorStyles(event.color ?? null, intensity) for chip backgrounds + 3px borders, or eventDotColor(event.color ?? null) for solid color indicators (#3679).',
      exemptions: new Map([
        // colorUtils.ts itself declares the helpers; the doc-comment
        // includes a literal `event.color` reference. The pattern is
        // anchored on a CSS property name, so the doc-comment line
        // shouldn't actually match — but if a future revision adds a
        // worked example with `backgroundColor: event.color` inside a
        // doc-comment, exempt it explicitly here.
      ]),
    },
  ],
});
