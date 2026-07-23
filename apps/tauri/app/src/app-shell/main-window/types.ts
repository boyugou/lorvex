import type { getAllLists } from '@/lib/ipc/tasks/lists';
import type { getOverview } from '@/lib/ipc/tasks/reviews';
import type { View } from '@/lib/types';

type OverviewData = Awaited<ReturnType<typeof getOverview>>;
export type ListsData = Awaited<ReturnType<typeof getAllLists>>;

export interface QuickCaptureInitialData {
  title?: string | undefined;
  list?: string | undefined;
  due?: string | undefined;
  priority?: number | undefined;
}

export interface MainWindowController {
  activeCommandPaletteSession: number | null;
  activeQuickCaptureSession: number | null;
  closeCommandPalette: (expectedSessionId?: number) => void;
  closeQuickCapture: (expectedSessionId?: number) => void;
  handleSidebarNavigate: (target: View) => void;
  usesMobileLayout: boolean;
  isOverviewError: boolean;
  lists: ListsData;
  mobileTitle: string;
  navigateToView: (target: View) => View;
  onRetryOverview: () => void;
  onSelectTask: (taskId: string | null) => void;
  openCommandPalette: () => void;
  openMobileLists: () => void;
  openQuickCapture: (data?: QuickCaptureInitialData) => void;
  quickCaptureInitialData: QuickCaptureInitialData | null;
  overview: OverviewData | null;
  selectMobileList: (listId: string) => void;
  selectedTaskId: string | null;
  setSelectedTaskId: (taskId: string | null) => void;
  showCapture: boolean;
  showPalette: boolean;
  startMainWindowDragging: () => void;
  toggleMainWindowZoom: () => Promise<void>;
  view: View;
}
