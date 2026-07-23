import { expect, test } from '@playwright/test';
import { installTauriMock } from './support/tauriMock';

const QUICK_CAPTURE_LABEL = /What needs to be done\?/i;

test.describe('main window smoke', () => {
  test.beforeEach(async ({ page }) => {
    await installTauriMock(page, 'en');
  });

  test('renders the desktop shell with primary navigation', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByRole('button', { name: 'Today', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Upcoming' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'All Tasks' })).toBeVisible();
    await expect(page.getByRole('button', { name: /Add task/i })).toBeVisible();
    await expect(page.getByRole('complementary').getByText('Lorvex', { exact: true })).toBeVisible();
  });

  test('opens quick capture from the sidebar action', async ({ page }) => {
    await page.goto('/');

    await page.getByRole('button', { name: /Add task/i }).click();
    await expect(page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL })).toBeVisible();
    await expect(page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL })).toBeFocused();
  });

  test('enables quick capture submission when a title is entered', async ({ page }) => {
    await page.goto('/');

    await page.getByRole('button', { name: /Add task/i }).click();
    await page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL }).fill('Ship Playwright smoke');
    await expect(page.getByRole('combobox', { name: QUICK_CAPTURE_LABEL })).toHaveValue('Ship Playwright smoke');
    await expect(page.getByRole('button', { name: 'Add Task', exact: true })).toBeEnabled();
  });
});
