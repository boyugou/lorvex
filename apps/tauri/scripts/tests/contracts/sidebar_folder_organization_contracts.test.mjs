import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('Sidebar is organized as a folder-backed subsystem with controller and content modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/Sidebar.tsx'), 'utf8');
  const controllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/sidebar/useSidebarController.ts'),
    'utf8',
  );
  const contentSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/sidebar/SidebarContent.tsx'),
    'utf8',
  );
  const navItemSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/sidebar/NavItem.tsx'),
    'utf8',
  );

  assert.match(rootSource, /import SidebarContent from '\.\/sidebar\/SidebarContent';/);
  assert.match(rootSource, /import \{ useSidebarController, type SidebarProps \} from '\.\/sidebar\/useSidebarController';/);
  assert.match(rootSource, /const controller = useSidebarController\(props\);/);
  assert.match(controllerSource, /export function useSidebarController\(/);
  assert.match(contentSource, /export default function SidebarContent/);
  assert.match(navItemSource, /export default.*function NavItem/);
});
