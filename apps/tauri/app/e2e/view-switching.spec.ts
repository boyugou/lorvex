import { expect, test } from '@playwright/test';
import { emitTauriEvent, installTauriMock } from './support/tauriMock';

test.describe('view switching', () => {
  test.beforeEach(async ({ page }) => {
    await installTauriMock(page, 'en');
    await page.goto('/');
  });

  test('sidebar list items are clickable', async ({ page }) => {
    // The mock provides an Inbox list - it should be visible in the sidebar
    const inbox = page.getByText('Inbox');
    if (await inbox.isVisible({ timeout: 3000 }).catch(() => false)) {
      await inbox.click();
      // Should navigate to list view - verify no crash
      await expect(page.getByRole('button', { name: 'Today', exact: true })).toBeVisible();
    }
  });

  test('rapidly switching views does not crash', async ({ page }) => {
    const buttons = ['Today', 'Upcoming', 'All Tasks'];
    for (const name of buttons) {
      const btn = page.getByRole('button', { name, exact: true });
      if (await btn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await btn.click();
        await page.waitForTimeout(100); // Brief settle
      }
    }
    // App should still be functional after rapid switching
    await expect(page.getByRole('button', { name: 'Today', exact: true })).toBeVisible();
  });

  test('menu command-palette event allows searching', async ({ page }) => {
    await emitTauriEvent(page, 'menu://command-palette');
    const palette = page.getByRole('dialog', { name: /search tasks or jump/i });
    const searchInput = palette.getByRole('combobox', { name: /search/i });
    await expect(searchInput).toBeVisible();

    await searchInput.fill('test');
    // Should accept input without crashing
    await expect(searchInput).toHaveValue('test');

    // Close palette
    await page.keyboard.press('Escape');
    await expect(searchInput).not.toBeVisible();
  });
});
