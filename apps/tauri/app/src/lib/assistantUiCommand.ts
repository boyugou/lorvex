import {
  APPEARANCE_PROFILES,
  ASSISTANT_UI_ACTIONS,
  ASSISTANT_UI_LANGUAGES,
  ASSISTANT_UI_VIEWS,
  THEME_MODES,
  type AppearanceProfile,
  type AssistantUiAction,
  type AssistantUiLanguage,
  type AssistantUiView,
} from '@lorvex/shared/types';
import { isValidLocale } from '../locales';
import { assertNever } from './errors/assertNever';
import { hasOnlyKeys, isPlainRecord as isRecord } from './objectGuards';
import type { ThemeMode } from './theme';
import type { View } from './types';

export interface AssistantUiCommand {
  command_id: string;
  action: AssistantUiAction;
  requested_at?: string | undefined;
  task_id?: string | undefined;
  view?: AssistantUiView | undefined;
  list_id?: string | undefined;
  theme?: ThemeMode | undefined;
  appearance_profile?: AppearanceProfile | undefined;
  language?: AssistantUiLanguage | undefined;
}

const ASSISTANT_UI_COMMAND_KEYS = new Set([
  'action',
  'appearance_profile',
  'command_id',
  'language',
  'list_id',
  'note',
  'requested_at',
  'requested_by',
  'task_id',
  'theme',
  'view',
]);

function hasOnlyAssistantUiCommandKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, ASSISTANT_UI_COMMAND_KEYS);
}

function isCanonicalNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim() !== '' && value === value.trim();
}

function optionalCanonicalString(value: unknown): string | undefined | null {
  if (value === null || value === undefined) return undefined;
  return isCanonicalNonEmptyString(value) ? value : null;
}

function optionalMetadataString(value: unknown): string | undefined | null {
  if (value === null || value === undefined) return undefined;
  return typeof value === 'string' ? value : null;
}

function optionalAssistantUiView(value: unknown): AssistantUiView | undefined | null {
  if (value === null || value === undefined) return undefined;
  return typeof value === 'string' && ASSISTANT_UI_VIEWS.includes(value as AssistantUiView)
    ? value as AssistantUiView
    : null;
}

function optionalThemeMode(value: unknown): ThemeMode | undefined | null {
  if (value === null || value === undefined) return undefined;
  return typeof value === 'string' && THEME_MODES.includes(value as ThemeMode)
    ? value as ThemeMode
    : null;
}

function optionalAppearanceProfile(value: unknown): AppearanceProfile | undefined | null {
  if (value === null || value === undefined) return undefined;
  return typeof value === 'string' && APPEARANCE_PROFILES.includes(value as AppearanceProfile)
    ? value as AppearanceProfile
    : null;
}

function optionalAssistantUiLanguage(value: unknown): AssistantUiLanguage | undefined | null {
  if (value === null || value === undefined) return undefined;
  if (value === 'system') return 'system';
  return typeof value === 'string' && isValidLocale(value) && ASSISTANT_UI_LANGUAGES.includes(value as AssistantUiLanguage)
    ? value as AssistantUiLanguage
    : null;
}

export function normalizeAssistantUiCommand(raw: unknown): AssistantUiCommand | null {
  if (!isRecord(raw) || !hasOnlyAssistantUiCommandKeys(raw)) return null;
  const command = raw;
  const commandId = isCanonicalNonEmptyString(command.command_id) ? command.command_id : null;
  const action = isCanonicalNonEmptyString(command.action) ? command.action : null;
  if (!commandId || !action) return null;
  if (!ASSISTANT_UI_ACTIONS.includes(action as AssistantUiAction)) return null;

  const requestedAt = optionalMetadataString(command.requested_at);
  const requestedBy = optionalMetadataString(command.requested_by);
  const note = optionalMetadataString(command.note);
  const taskId = optionalCanonicalString(command.task_id);
  const view = optionalAssistantUiView(command.view);
  const listId = optionalCanonicalString(command.list_id);
  const theme = optionalThemeMode(command.theme);
  const appearanceProfile = optionalAppearanceProfile(command.appearance_profile);
  const language = optionalAssistantUiLanguage(command.language);
  if (
    requestedAt === null
    || requestedBy === null
    || note === null
    || taskId === null
    || view === null
    || listId === null
    || theme === null
    || appearanceProfile === null
    || language === null
  ) {
    return null;
  }

  switch (action as AssistantUiAction) {
    case 'enter_focus_mode':
    case 'exit_focus_mode':
      break;
    case 'focus_task':
    case 'open_task':
      if (!taskId) return null;
      break;
    case 'switch_view':
      if (!view) return null;
      if (view === 'list' && !listId) return null;
      break;
    case 'set_theme':
      if (!theme) return null;
      break;
    case 'set_appearance_profile':
      if (!appearanceProfile) return null;
      break;
    case 'set_language':
      if (!language) return null;
      break;
    default:
      return assertNever(action as never, 'assistant UI action');
  }

  return {
    command_id: commandId,
    action: action as AssistantUiAction,
    requested_at: requestedAt,
    task_id: taskId,
    view,
    list_id: listId,
    theme,
    appearance_profile: appearanceProfile,
    language,
  };
}

export function assistantCommandViewToAppView(
  view: AssistantUiView | undefined,
  listId?: string,
): View | null {
  if (!view) return null;

  switch (view) {
    case 'today': return { type: 'today' };
    case 'upcoming': return { type: 'upcoming' };
    case 'ai_changelog': return { type: 'ai_changelog' };
    case 'all_tasks': return { type: 'all_tasks' };
    case 'someday': return { type: 'someday' };
    case 'calendar': return { type: 'calendar' };
    case 'eisenhower': return { type: 'eisenhower' };
    case 'kanban': return { type: 'kanban' };
    case 'dependencies': return { type: 'dependencies' };
    case 'memory': return { type: 'memory' };
    case 'review': return { type: 'review' };
    case 'daily_review': return { type: 'daily_review' };
    case 'settings': return { type: 'settings' };
    case 'habits': return { type: 'habits' };
    case 'recurring': return { type: 'recurring' };
    case 'list':
      return listId ? { type: 'list', listId } : null;
  }

  return assertNever(view, 'assistant UI view');
}
