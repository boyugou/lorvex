import { test, expect, type Page } from '@playwright/test';
import { E2E_FIXTURE_NOW, installTauriMock } from './support/tauriMock';
import ar from '../src/locales/ar.json' with { type: 'json' };
import en from '../src/locales/en.json' with { type: 'json' };
import zhHant from '../src/locales/zh-Hant.json' with { type: 'json' };
import zh from '../src/locales/zh.json' with { type: 'json' };

/**
 * i18n visual regression tests.
 *
 * These tests navigate to the app in different locales and capture screenshots
 * for comparison against baseline images. The goal is to catch:
 *   - Text overflow / truncation when switching languages
 *   - RTL layout issues (Arabic, Hebrew, Farsi, Urdu)
 *   - Missing translation keys showing raw keys in the UI
 *   - Font rendering or spacing regressions
 *
 * How to run:
 *   1. Start the dev server:  npm run -w app tauri:dev
 *   2. Run tests:             npx -w app playwright test e2e/i18n-visual.spec.ts
 *   3. Update baselines:      npx -w app playwright test e2e/i18n-visual.spec.ts --update-snapshots
 *
 * Note: The Tauri IPC layer is not available in a plain browser context, so
 * these tests install the shared Tauri mock before navigation. Locale
 * preferences must match the real backend contract: `get_preference` returns
 * the JSON string stored by `setPreference`, not a bare locale code.
 */

// Locales to test: LTR English, Simplified/Traditional Chinese, and RTL Arabic.
const TEST_LOCALES = [
  { code: 'en', name: 'English', dir: 'ltr' },
  { code: 'zh', name: 'Simplified Chinese', dir: 'ltr' },
  { code: 'zh-Hant', name: 'Traditional Chinese', dir: 'ltr' },
  { code: 'ar', name: 'Arabic', dir: 'rtl' },
] as const;
type TestLocale = typeof TEST_LOCALES[number];
type LocaleCode = TestLocale['code'];
type LocaleCatalog = Record<string, string>;

const LOCALE_CATALOGS: Record<LocaleCode, LocaleCatalog> = {
  ar,
  en,
  zh,
  'zh-Hant': zhHant,
};

function label(locale: TestLocale, key: string): string {
  return LOCALE_CATALOGS[locale.code][key] ?? key;
}

async function loadLocalizedApp(page: Page, locale: TestLocale) {
  await page.goto('/');
  await page.waitForSelector('[data-testid="sidebar"], nav, aside', {
    timeout: 15_000,
  });
  await expect(page.locator('html')).toHaveAttribute('lang', locale.code);
  await expect(page.locator('html')).toHaveAttribute('dir', locale.dir);
}

async function settleVisualState(page: Page) {
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(500);
}

// Key views to screenshot. Each entry is a route/hash or a description of
// what to navigate to. Since Lorvex is a single-page app with view state
// managed in React, we use the sidebar to navigate.
const VIEWS_TO_CAPTURE = [
  {
    name: 'today',
    description: 'Today view (default landing page)',
  },
  {
    name: 'all-tasks',
    description: 'All Tasks dense list',
    prepare: async (page, locale) => {
      await page.getByRole('button', { name: label(locale, 'nav.allTasks'), exact: true }).click();
    },
  },
  {
    name: 'calendar',
    description: 'Calendar view',
    prepare: async (page, locale) => {
      await page.getByRole('button', { name: label(locale, 'nav.calendar'), exact: true }).click();
    },
  },
  {
    name: 'settings',
    description: 'Settings view',
    prepare: async (page, locale) => {
      await page.getByRole('button', { name: label(locale, 'nav.settings'), exact: true }).click();
    },
  },
  {
    name: 'quick-capture',
    description: 'Quick Capture modal',
    prepare: async (page, locale) => {
      await page.getByRole('button', { name: label(locale, 'capture.addTask') }).first().click();
      await expect(page.getByRole('dialog')).toBeVisible();
    },
  },
] as const;

test.describe('i18n visual regression', () => {
  for (const locale of TEST_LOCALES) {
    test.describe(`locale: ${locale.name} (${locale.code})`, () => {

      test.beforeEach(async ({ page }) => {
        await page.clock.setFixedTime(new Date(E2E_FIXTURE_NOW));
        await installTauriMock(page, locale.code);
      });

      for (const view of VIEWS_TO_CAPTURE) {
        test(`${view.name} view renders correctly`, async ({ page }) => {
          await loadLocalizedApp(page, locale);
          if ('prepare' in view) {
            await view.prepare(page, locale);
          }
          await settleVisualState(page);

          // Capture a full-page screenshot for comparison.
          await expect(page).toHaveScreenshot(
            `${view.name}-${locale.code}.png`,
            {
              fullPage: true,
              // RTL layouts may have different scrollbar positions; mask them.
              mask: [],
            },
          );
        });
      }

      test.describe('mobile shell viewport', () => {
        test.use({ viewport: { width: 390, height: 844 } });

        test('mobile shell renders correctly', async ({ page }) => {
          await loadLocalizedApp(page, locale);
          await settleVisualState(page);

          await expect(page).toHaveScreenshot(
            `mobile-shell-${locale.code}.png`,
            { fullPage: true },
          );
        });
      });

      if (locale.dir === 'rtl') {
        test('document direction is RTL', async ({ page }) => {
          await page.goto('/');
          await page.waitForSelector('[data-testid="sidebar"], nav, aside', {
            timeout: 15_000,
          });

          await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
        });
      }
    });
  }
});
