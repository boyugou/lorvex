import { useI18n } from '@/lib/i18n';
import type { View } from '@/lib/types';

import { SparkleIcon } from './icons';
import ModuleStatePanel from './ModuleStatePanel';

interface AssistantNotConfiguredPanelProps {
  /**
   * Called with `{ type: 'settings', sectionId: 'settings-section-mcp' }`
   * so the host view can defer navigation through the existing
   * MainViewContent router. Optional — if omitted, the CTA button is
   * hidden and the panel degrades to an informational card.
   */
  onNavigate?: ((view: View) => void) | undefined;
}

/**
 * shared "Connect your AI assistant" empty state used by
 * views that assume an MCP-capable assistant is already writing data
 * (ChangelogView, AIMemoryView, DailyReviewView, HabitsView). Rendered
 * only when the hoisted `mcpServerStatus.resolved === false` AND the
 * view's existing data-empty condition is met — so a freshly-empty
 * configured assistant still shows the normal "will log here" copy,
 * and an un-configured user sees the setup CTA instead.
 *
 * Wraps `ModuleStatePanel` so look-and-feel stays in lock-step with
 * every other empty state in the product (icon + title + subtitle +
 * single CTA button). The only new behaviour is the deep-link into
 * Settings → Assistant MCP via the `sectionId` param that
 * `MainViewContent` forwards to `SettingsView`.
 */
export default function AssistantNotConfiguredPanel({
  onNavigate,
}: AssistantNotConfiguredPanelProps) {
  const { t } = useI18n();
  const actionProps = onNavigate
    ? {
        actionLabel: t('mcpNotConfigured.cta'),
        onAction: () => onNavigate({ type: 'settings', sectionId: 'settings-section-mcp' }),
      }
    : {};
  return (
    <ModuleStatePanel
      icon={<SparkleIcon className="w-9 h-9" />}
      title={t('mcpNotConfigured.title')}
      subtitle={t('mcpNotConfigured.hint')}
      {...actionProps}
    />
  );
}
