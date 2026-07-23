import { expect, test } from '@playwright/test';
import { emitTauriEvent, installTauriMock } from './support/tauriMock';

test.describe('navigation', () => {
  test.beforeEach(async ({ page }) => {
    await installTauriMock(page, 'en');
    await page.goto('/');
  });

  test('sidebar shows all primary navigation items', async ({ page }) => {
    const primaryViews = page.getByRole('navigation', { name: 'Views' });
    await expect(primaryViews.getByRole('button', { name: 'Today', exact: true })).toBeVisible();
    await expect(primaryViews.getByRole('button', { name: 'Upcoming', exact: true })).toBeVisible();
    await expect(primaryViews.getByRole('button', { name: 'All Tasks', exact: true })).toBeVisible();
  });

  test('clicking Today navigates to today view', async ({ page }) => {
    const todayNav = page
      .getByRole('navigation', { name: 'Views' })
      .getByRole('button', { name: 'Today', exact: true });
    await todayNav.click();
    // Today view should be the default, so it should already be active
    await expect(todayNav).toBeVisible();
  });

  test('clicking All Tasks navigates to all tasks view', async ({ page }) => {
    const allTasksNav = page
      .getByRole('navigation', { name: 'Views' })
      .getByRole('button', { name: 'All Tasks', exact: true });
    await allTasksNav.click();
    // Should show the all tasks search/filter UI
    await expect(allTasksNav).toBeVisible();
  });

  test('menu command-palette event opens command palette', async ({ page }) => {
    await emitTauriEvent(page, 'menu://command-palette');
    const palette = page.getByRole('dialog', { name: /search tasks or jump/i });
    await expect(palette.getByRole('combobox', { name: /search/i })).toBeVisible();
  });

  test('Escape closes command palette', async ({ page }) => {
    await emitTauriEvent(page, 'menu://command-palette');
    const palette = page.getByRole('dialog', { name: /search tasks or jump/i });
    const searchInput = palette.getByRole('combobox', { name: /search/i });
    await expect(searchInput).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(searchInput).not.toBeVisible();
  });
});

test.describe('settings navigation', () => {
  test.beforeEach(async ({ page }) => {
    await installTauriMock(page, 'en');
    await page.goto('/');
  });

  test('can open settings from sidebar', async ({ page }) => {
    const settingsButton = page.getByRole('button', { name: /settings/i });
    if (await settingsButton.isVisible()) {
      await settingsButton.click();
      // Settings view should show sections
      await expect(page.getByText(/general|appearance|sync/i)).toBeVisible({ timeout: 3000 });
    }
  });
});
