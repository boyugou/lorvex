import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ReactNode } from 'react';

import type { MainWindowController } from './types';
import { MobileMainWindow } from './MobileMainWindow';

const mobileMainWindowTestState = vi.hoisted(() => ({
  forceMoreMenuOpen: false,
  stateCallIndex: 0,
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useState: vi.fn((initialValue: unknown) => {
      mobileMainWindowTestState.stateCallIndex += 1;
      const value = typeof initialValue === 'function'
        ? (initialValue as () => unknown)()
        : initialValue;

      if (mobileMainWindowTestState.forceMoreMenuOpen && mobileMainWindowTestState.stateCallIndex === 1) {
        return [true, vi.fn()];
      }

      return [value, vi.fn()];
    }),
  };
});

vi.mock('@/components/MainViewContent', () => ({
  default: () => <div data-testid="main-view" />,
}));

vi.mock('@/components/ui/overlay', () => ({
  ModalShell: ({ open, children, panelClassName, ariaLabel }: {
    open: boolean;
    children: ReactNode;
    panelClassName?: string;
    ariaLabel?: string;
  }) => (open ? (
    <div role="dialog" aria-label={ariaLabel} className={panelClassName}>
      {children}
    </div>
  ) : null),
}));

vi.mock('@/lib/useVisualViewport', () => ({
  useVisualViewportInset: vi.fn(),
}));

vi.mock('@/lib/i18n', () => ({
  useI18n: () => ({
    locale: 'en',
    t: (key: string) => ({
      'allTasks.search': 'Search',
      'capture.addTask': 'Add task',
      'common.more': 'More',
      'nav.ai_changelog': 'Changelog',
      'nav.allTasks': 'All Tasks',
      'nav.calendar': 'Calendar',
      'nav.changelog': 'Changelog',
      'nav.daily_review': 'Daily Review',
      'nav.dependencies': 'Dependencies',
      'nav.eisenhower': 'Matrix',
      'nav.habits': 'Habits',
      'nav.kanban': 'Kanban',
      'nav.lists': 'Lists',
      'nav.memory': 'Memory',
      'nav.primary': 'Primary',
      'nav.recurring': 'Recurring',
      'nav.review': 'Review',
      'nav.settings': 'Settings',
      'nav.someday': 'Someday',
      'nav.today': 'Today',
      'nav.upcoming': 'Upcoming',
    }[key] ?? key),
    formatNumber: (value: number) => `#${value}#`,
  }),
}));

function createController(overrides: Partial<MainWindowController> = {}): MainWindowController {
  return {
    activeCommandPaletteSession: null,
    activeQuickCaptureSession: null,
    closeCommandPalette: vi.fn(),
    closeQuickCapture: vi.fn(),
    handleSidebarNavigate: vi.fn(),
    usesMobileLayout: true,
    isOverviewError: false,
    lists: [],
    mobileTitle: 'Today',
    navigateToView: vi.fn((target) => target),
    onRetryOverview: vi.fn(),
    onSelectTask: vi.fn(),
    openCommandPalette: vi.fn(),
    openMobileLists: vi.fn(),
    openQuickCapture: vi.fn(),
    quickCaptureInitialData: null,
    overview: {
      stats: {
        today_pool_count: 1_234,
      },
    } as MainWindowController['overview'],
    selectMobileList: vi.fn(),
    selectedTaskId: null,
    setSelectedTaskId: vi.fn(),
    showCapture: false,
    showPalette: false,
    startMainWindowDragging: vi.fn(),
    toggleMainWindowZoom: vi.fn(async () => {}),
    view: { type: 'today' },
    ...overrides,
  };
}

beforeEach(() => {
  mobileMainWindowTestState.forceMoreMenuOpen = false;
  mobileMainWindowTestState.stateCallIndex = 0;
});

describe('MobileMainWindow tab badges', () => {
  it('hides visual badge text from assistive tech and labels the tab with the localized count', () => {
    const html = renderToStaticMarkup(<MobileMainWindow controller={createController()} />);

    expect(html).toContain('aria-label="Today, 1,234 tasks today"');
    expect(html).toContain('aria-hidden="true"');
    expect(html).toContain('#99#+');
  });
});

describe('MobileMainWindow More sheet layout', () => {
  it('uses an adaptive grid and wrap-safe labels for long localized destinations', () => {
    mobileMainWindowTestState.forceMoreMenuOpen = true;

    const html = renderToStaticMarkup(<MobileMainWindow controller={createController()} />);

    expect(html).toContain('grid-template-columns:repeat(auto-fit, minmax(min(5.5rem, 100%), 1fr))');
    expect(html).toContain('min-w-0');
    expect(html).toContain('whitespace-normal');
    expect(html).toContain('break-words');
    expect(html).toContain('hyphens-auto');
  });
});
