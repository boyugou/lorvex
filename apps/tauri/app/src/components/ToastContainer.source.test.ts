import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('ToastContainer mobile width contract (#4284)', () => {
  it('keeps long actionable toast text inside a 320px viewport with controls reachable', () => {
    const source = fs.readFileSync('src/components/ToastContainer.tsx', 'utf8');

    expect(source).toContain('px-3');
    expect(source).toContain('w-[min(calc(100vw_-_1.5rem),24rem)]');
    expect(source).toContain('items-start');
    expect(source).toContain('min-w-0 flex-1 break-words');
    // Mobile tap-target: `min-tap` (44×44 utility) replaces
    // the raw `min-w-[44px] min-h-[44px]` literals.
    expect(source).toMatch(
      /const TOAST_ACTION_BTN_CLASS =[\s\S]*RUNTIME_PROFILE\.runtimeClass === 'mobile'[\s\S]*min-tap[\s\S]*max-w-\[7rem\][\s\S]*break-words/,
    );
    expect(source).toMatch(
      /className=\{TOAST_ACTION_BTN_CLASS\}/,
    );
  });
});
