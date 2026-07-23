import type { ReactNode } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { QuickCaptureInitialData } from '@/app-shell/main-window/types';
import type { View } from '@/lib/types';

export interface CommandPaletteProps {
  onClose: () => void;
  onNavigate: (view: View) => void;
  onSelectTask: (taskId: string) => void;
  onQuickCapture: (data?: QuickCaptureInitialData) => void;
}

export type PaletteNavItem = {
  kind: 'nav';
  label: string;
  icon: ReactNode;
  shortcut?: string | undefined;
  view: View;
};

export type PaletteActionItem = {
  kind: 'action';
  label: string;
  icon: ReactNode;
  shortcut?: string | undefined;
  action: () => void;
};

type PaletteTaskItem = {
  kind: 'task';
  task: Task;
};

export type ResultItem = PaletteNavItem | PaletteActionItem | PaletteTaskItem;

/**
 * Editorial palette section. Sits above the structural `kind`
 * discriminator: a `frequent` row may be `action`-shaped, a `recent`
 * row may be either `nav` or `action`. The renderer groups by
 * `section ?? item.kind` so Spotlight-style eyebrows ("Recently
 * used" / "Frequent tasks" / "Navigate" / "Actions") survive even
 * when two adjacent items share a `kind`.
 */
export type PaletteSection = 'recent' | 'frequent' | 'nav' | 'action' | 'task';

export interface KeyedResult {
  key: string;
  item: ResultItem;
  /// Optional editorial section override; when absent the renderer
  /// falls back to `item.kind` (so the empty-query / no-recents flow
  /// keeps its prior grouping unchanged).
  section?: PaletteSection;
}
