import { expect, test } from '@playwright/test';
import { emitTauriEvent, installTauriMock } from './support/tauriMock';

const QUICK_CAPTURE_LABEL = /What needs to be done\?/i;
const tomorrowYmd = localYmdOffset(1);
const tomorrowAccessibleLabel = accessibleDateLabel(tomorrowYmd);
const MOBILE_LONG_LIST = {
  id: 'list-mobile-long',
  name: 'Extremely long mobile planning list name for overflow verification',
  color: null,
  icon: '📱',
  description: null,
  archived_at: null,
  created_at: '2026-03-30T09:00:00.000Z',
  updated_at: '2026-03-30T09:00:00.000Z',
  open_count: 12,
};

const MANY_TAGS = [
  { display_name: 'tag-alpha', color: '#ef4444' },
  { display_name: 'tag-beta', color: '#f97316' },
  { display_name: 'tag-gamma', color: '#eab308' },
  { display_name: 'tag-delta', color: '#22c55e' },
  { display_name: 'tag-epsilon', color: '#14b8a6' },
  { display_name: 'tag-zeta', color: '#3b82f6' },
  { display_name: 'tag-eta', color: '#6366f1' },
  { display_name: 'tag-theta', color: '#a855f7' },
  { display_name: 'tag-iota', color: '#ec4899' },
];

test.describe('quick capture', () => {
  test.beforeEach(async ({ page }) => {
    await installTauriMock(page, 'en');
    await page.goto('/');
  });

  test('menu quick-capture event opens quick capture', async ({ page }) => {
    await emitTauriEvent(page, 'menu://quick-capture');
    await expect(page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL })).toBeVisible({ timeout: 2000 });
  });

  test('typing a title enables the submit button', async ({ page }) => {
    await page.getByRole('button', { name: /Add task/i }).click();
    const input = page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL });
    await input.fill('Buy groceries');
    await expect(page.getByRole('button', { name: 'Add Task', exact: true })).toBeEnabled();
  });

  test('empty title keeps submit disabled', async ({ page }) => {
    await page.getByRole('button', { name: /Add task/i }).click();
    const input = page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL });
    await input.fill('');
    await expect(page.getByRole('button', { name: 'Add Task', exact: true })).toBeDisabled();
  });

  test('submit calls quick_capture IPC with correct title', async ({ page }) => {
    await page.getByRole('button', { name: /Add task/i }).click();
    const input = page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL });
    await input.fill('Ship Playwright tests');
    await page.getByRole('button', { name: 'Add Task', exact: true }).click();

    // Verify the mock captured the IPC call
    const calls = await page.evaluate(() => {
      const w = window as typeof window & {
        __LORVEX_E2E__?: { quickCaptureCalls: Array<Record<string, unknown> | undefined> };
      };
      return w.__LORVEX_E2E__?.quickCaptureCalls ?? [];
    });
    expect(calls.length).toBeGreaterThan(0);
    expect(calls[0]?.title).toBe('Ship Playwright tests');
  });

  test('custom date picker selection is submitted as the due date', async ({ page }) => {
    await page.getByRole('button', { name: /Add task/i }).click();
    const input = page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL });
    await input.fill('Schedule custom due date');

    await page.getByRole('button', { name: 'Pick date' }).click();
    const picker = page.getByRole('dialog', { name: 'Pick date' });
    await expect(picker).toBeVisible();
    await picker.getByRole('button', { name: tomorrowAccessibleLabel }).click();
    await expect(picker).not.toBeVisible();
    await expect(page.getByText(tomorrowYmd)).toBeVisible();

    await page.getByRole('button', { name: 'Add Task', exact: true }).click();

    const calls = await page.evaluate(() => {
      const w = window as typeof window & {
        __LORVEX_E2E__?: { quickCaptureCalls: Array<Record<string, unknown> | undefined> };
      };
      return w.__LORVEX_E2E__?.quickCaptureCalls ?? [];
    });
    expect(calls.length).toBeGreaterThan(0);
    expect(calls[0]?.title).toBe('Schedule custom due date');
    expect(calls[0]?.due_date).toBe(tomorrowYmd);
  });

  test('Escape closes quick capture without submitting', async ({ page }) => {
    await page.getByRole('button', { name: /Add task/i }).click();
    await expect(page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL })).toBeVisible();

    await page.keyboard.press('Escape');
    // Quick capture should close
    await expect(page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL })).not.toBeVisible({ timeout: 2000 });

    // No IPC call should have been made
    const calls = await page.evaluate(() => {
      const w = window as typeof window & {
        __LORVEX_E2E__?: { quickCaptureCalls: Array<Record<string, unknown> | undefined> };
      };
      return w.__LORVEX_E2E__?.quickCaptureCalls ?? [];
    });
    expect(calls.length).toBe(0);
  });
});

test.describe('quick capture mobile layout', () => {
  test.use({ viewport: { width: 390, height: 520 }, isMobile: true });

  test.beforeEach(async ({ page }) => {
    await installTauriMock(page, 'en', {
      lists: [MOBILE_LONG_LIST],
      tags: MANY_TAGS,
    });
    await page.goto('/');
  });

  test('keeps footer and tag suggestions inside the mobile viewport', async ({ page }) => {
    await page.getByRole('button', { name: /Add task/i }).click();
    await page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL }).fill('Mobile overflow check');
    await page.getByRole('button', { name: 'Today' }).click();
    await page.getByRole('button', { name: 'Tags (comma-separated)' }).click();
    const tagInput = page.getByRole('combobox', { name: 'Tags (comma-separated)' });
    await tagInput.fill('tag');

    const tagListbox = page.getByRole('listbox');
    await expect(tagListbox).toBeVisible();
    const listboxBox = await tagListbox.boundingBox();
    const inputBox = await tagInput.boundingBox();
    const viewport = page.viewportSize();

    expect(listboxBox).not.toBeNull();
    expect(inputBox).not.toBeNull();
    expect(viewport).not.toBeNull();
    expect(listboxBox!.x).toBeGreaterThanOrEqual(0);
    expect(listboxBox!.x + listboxBox!.width).toBeLessThanOrEqual(viewport!.width);
    expect(listboxBox!.y).toBeGreaterThanOrEqual(0);
    expect(listboxBox!.y + listboxBox!.height).toBeLessThanOrEqual(viewport!.height);
    await expect(documentScrollWidth(page)).resolves.toBeLessThanOrEqual(viewport!.width);
  });

  test('restores focus to priority and duration triggers after popover dismissals', async ({ page }) => {
    await page.getByRole('button', { name: /Add task/i }).click();
    await page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL }).fill('Focus restore check');

    const priorityTrigger = page.getByRole('button', { name: 'Priority' });
    await priorityTrigger.click();
    await expect(page.getByRole('menu', { name: 'Priority' })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(priorityTrigger).toBeFocused();

    await priorityTrigger.click();
    await page.getByRole('menuitemradio', { name: 'P1' }).click();
    const selectedPriorityTrigger = page.getByRole('button', { name: 'P1' });
    await expect(selectedPriorityTrigger).toBeFocused();

    await selectedPriorityTrigger.click();
    await page.getByRole('menuitem', { name: 'Clear' }).click();
    await expect(priorityTrigger).toBeFocused();

    const durationTrigger = page.getByRole('button', { name: 'min' });
    await durationTrigger.click();
    await expect(page.getByRole('dialog', { name: 'min' })).toBeVisible();
    await page.getByRole('button', { name: '15m' }).click();
    const selectedDurationTrigger = page.getByRole('button', { name: '15m' });
    await expect(selectedDurationTrigger).toBeFocused();

    await selectedDurationTrigger.click();
    await page.getByRole('dialog', { name: 'min' }).getByRole('button', { name: 'Clear' }).click();
    await expect(durationTrigger).toBeFocused();
  });
});

async function documentScrollWidth(page: import('@playwright/test').Page): Promise<number> {
  return page.evaluate(() => document.documentElement.scrollWidth);
}

function localYmdOffset(offsetDays: number): string {
  const date = new Date();
  date.setDate(date.getDate() + offsetDays);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function accessibleDateLabel(ymd: string): string {
  const [year, month, day] = ymd.split('-').map(Number);
  return new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(new Date(year, month - 1, day));
}
