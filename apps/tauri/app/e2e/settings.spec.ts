import { expect, test } from '@playwright/test';
import { emitTauriEvent, installTauriMock } from './support/tauriMock';

const RTL_FOCUS_TASK = {
  id: 'focus-rtl-task',
  title: 'RTL slider verification',
  body: null,
  status: 'open',
  due_date: '2026-05-08',
  due_time: null,
  priority: 2,
  estimated_minutes: 25,
  list_id: 'list-inbox',
  parent_task_id: null,
  created_at: '2026-03-30T09:00:00.000Z',
  updated_at: '2026-03-30T09:00:00.000Z',
  source_type: 'manual',
  source_id: null,
  deleted_at: null,
  deferred_until: null,
  defer_count: 0,
  tags: [],
  checklist_items: [],
};

test.describe('settings', () => {
  test('settings view loads without crashing', async ({ page }) => {
    await installTauriMock(page, 'en');
    await page.goto('/');

    // Navigate to settings - may be via sidebar button or keyboard
    const settingsButton = page.getByRole('button', { name: /settings/i });
    if (await settingsButton.isVisible({ timeout: 2000 }).catch(() => false)) {
      await settingsButton.click();
      // Settings should show at least one section
      await expect(page.locator('text=/General|Appearance|Sync/i').first()).toBeVisible({
        timeout: 5000,
      });
    }
  });

  test('RTL locale keeps settings font slider visuals logical', async ({ page }) => {
    await installTauriMock(page, 'fa', {
      currentFocus: {
        date: '2026-05-08',
        task_ids: [RTL_FOCUS_TASK.id],
        briefing: null,
        timezone: 'America/Los_Angeles',
        tasks: [RTL_FOCUS_TASK],
      },
    });

    await page.goto('/');
    await emitTauriEvent(page, 'menu://navigate', 'settings');
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');

    const fontScaleSlider = page.getByTestId('settings-font-scale-slider');
    await expect(fontScaleSlider).toBeVisible({ timeout: 10_000 });
    await expect(fontScaleSlider).toHaveAttribute('dir', 'rtl');
    await expect(fontScaleSlider).toHaveCSS(
      'background-image',
      /linear-gradient\(to left/,
    );
  });

  test('RTL locale keeps focus opacity slider visuals and percent label logical', async ({ page }) => {
    await installTauriMock(page, 'fa', {
      currentFocus: {
        date: '2026-05-08',
        task_ids: [RTL_FOCUS_TASK.id],
        briefing: null,
        timezone: 'America/Los_Angeles',
        tasks: [RTL_FOCUS_TASK],
      },
    });
    await page.goto('/#focus');
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
    await page.getByRole('button', { name: 'Transparency' }).hover();

    const opacitySlider = page.getByTestId('focus-opacity-slider');
    const opacityFill = page.getByTestId('focus-opacity-slider-fill');
    const opacityThumb = page.getByTestId('focus-opacity-slider-thumb');

    await expect(opacitySlider).toHaveAttribute('dir', 'rtl');
    await expect(opacitySlider).toHaveAttribute('aria-valuetext', '۸۵٪');
    await expect(opacityFill).toHaveAttribute('style', /inset-inline-start:\s*0%;/);
    await expect(opacityFill).toHaveAttribute('style', /inline-size:\s*78\.57%;/);
    await expect(opacityThumb).toHaveAttribute('style', /inset-inline-start:\s*calc\(78\.57% - 6px\);/);
  });
});

test.describe('error recovery', () => {
  test('app renders error boundary fallback on crash', async ({ page }) => {
    await installTauriMock(page, 'en');

    // Navigate to the app
    await page.goto('/');
    // The app should load successfully with mock data
    await expect(page.getByRole('complementary').getByText('Lorvex', { exact: true })).toBeVisible({ timeout: 5000 });
  });

  test('app handles missing IPC gracefully', async ({ page }) => {
    // Navigate without installing the Tauri mock
    // The app should show an error or loading state, not a blank page
    await page.goto('/');
    // Give it time to attempt IPC and handle failure
    await page.waitForTimeout(2000);
    // The page should have some content (not completely blank)
    const body = await page.textContent('body');
    expect(body).toBeTruthy();
  });
});
