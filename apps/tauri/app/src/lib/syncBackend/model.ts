import type { RuntimeProfile } from '../platform/platform';
import {
  SYNC_BACKEND_FILESYSTEM_BRIDGE,
  SYNC_BACKEND_PRIORITY,
  type SyncBackendKind,
} from './kinds.ts';

type SyncBackendConfigEditorKind = 'none' | 'filesystem_root_path';
type SyncBackendDiagnosticsKind = 'none' | 'filesystem_bridge';

interface FilesystemBridgeBackendConfig {
  rootPath: string;
}

export interface SyncBackendConfigs {
  filesystem_bridge: FilesystemBridgeBackendConfig;
}

export interface SyncBackendSupportContext {
  availableBackendKinds: readonly SyncBackendKind[];
}

export interface SyncBackendSettings {
  enabled: boolean;
  configuredBackendKind: SyncBackendKind | null;
  effectiveBackendKind: SyncBackendKind | null;
  backendConfigs: SyncBackendConfigs;
}

export interface SyncBackendConfig {
  kind: typeof SYNC_BACKEND_FILESYSTEM_BRIDGE;
  config: FilesystemBridgeBackendConfig;
}

export interface SyncBackendDescriptor<K extends SyncBackendKind = SyncBackendKind> {
  kind: K;
  configEditorKind: SyncBackendConfigEditorKind;
  diagnosticsKind: SyncBackendDiagnosticsKind;
}

export interface ResolvedSyncBackend {
  requestedBackendKind: SyncBackendKind | null;
  effectiveBackendKind: SyncBackendKind | null;
  shouldNormalizeBackendKind: boolean;
}

export interface ResolveSyncBackendOptions extends SyncBackendSupportContext {
  requestedBackendKindRaw: string | null;
}

export interface RunSyncBackendOptions {
  backend: SyncBackendConfig;
  maxEvents: number;
  maxConsecutiveRepulls: number;
  quickRetryMs: number;
  isCancelled: () => boolean;
  wait: (delayMs: number) => Promise<void>;
}

export interface RunSyncBackendResult {
  quickRetryRequested: boolean;
  nextDelayOverrideMs: number | null;
}

export interface RunSyncBackendNowOptions {
  backend: SyncBackendConfig;
  maxEvents: number;
}

const SYNC_BACKEND_DESCRIPTORS: Record<SyncBackendKind, SyncBackendDescriptor> = {
  [SYNC_BACKEND_FILESYSTEM_BRIDGE]: {
    kind: SYNC_BACKEND_FILESYSTEM_BRIDGE,
    configEditorKind: 'filesystem_root_path',
    diagnosticsKind: 'filesystem_bridge',
  },
};
const syncBackendSupportContextCache = new Map<string, SyncBackendSupportContext>();

export interface SyncBackendRunSummary {
  pushed: number;
  pulledRemoteEvents: number;
  applied: number;
  pushErrors: number;
  pullLimitHit: boolean;
  diagnosticsLogFailures: number;
}

export interface RunSyncBackendNowResult {
  backendKind: typeof SYNC_BACKEND_FILESYSTEM_BRIDGE;
  backendResult: import('../ipc/sync').FilesystemBridgeSyncResult | null;
  summary: SyncBackendRunSummary;
}

export function getSyncBackendSupportContext(
  runtimeProfile: Pick<RuntimeProfile, 'supportedSyncBackendKinds'>,
): SyncBackendSupportContext {
  const cacheKey = runtimeProfile.supportedSyncBackendKinds.join('\0');
  const cached = syncBackendSupportContextCache.get(cacheKey);
  if (cached) return cached;
  const context = {
    availableBackendKinds: runtimeProfile.supportedSyncBackendKinds,
  };
  syncBackendSupportContextCache.set(cacheKey, context);
  return context;
}

export function getSyncBackendDescriptor<K extends SyncBackendKind>(
  backendKind: K,
): SyncBackendDescriptor<K> {
  return SYNC_BACKEND_DESCRIPTORS[backendKind] as SyncBackendDescriptor<K>;
}

export function getDefaultSyncBackendKind(
  options: SyncBackendSupportContext,
): SyncBackendKind | null {
  return SYNC_BACKEND_PRIORITY.find((backendKind) => supportsSyncBackend(backendKind, options))
    ?? null;
}

function coerceSyncBackendKind(raw: string | null): SyncBackendKind | null {
  if (!raw?.trim()) {
    return null;
  }
  if (raw.trim() === SYNC_BACKEND_FILESYSTEM_BRIDGE) {
    return SYNC_BACKEND_FILESYSTEM_BRIDGE;
  }
  return null;
}

export function createDefaultSyncBackendConfigs(
  defaultRootPath = '',
): SyncBackendConfigs {
  return {
    filesystem_bridge: {
      rootPath: defaultRootPath.trim(),
    },
  };
}

function supportsSyncBackend(
  backendKind: SyncBackendKind,
  options: SyncBackendSupportContext,
): boolean {
  return options.availableBackendKinds.includes(backendKind);
}

export function listAvailableSyncBackends(
  options: SyncBackendSupportContext,
): SyncBackendKind[] {
  return SYNC_BACKEND_PRIORITY.filter((backendKind) => supportsSyncBackend(backendKind, options));
}

export function resolveSyncBackend(
  options: ResolveSyncBackendOptions,
): ResolvedSyncBackend {
  const requestedBackendKind = coerceSyncBackendKind(options.requestedBackendKindRaw);
  const effectiveBackendKind = requestedBackendKind !== null && supportsSyncBackend(requestedBackendKind, options)
    ? requestedBackendKind
    : getDefaultSyncBackendKind(options);
  return {
    requestedBackendKind,
    effectiveBackendKind,
    shouldNormalizeBackendKind: effectiveBackendKind !== requestedBackendKind,
  };
}

export function syncBackendUsesFilesystemRootPathEditor(
  backendKind: SyncBackendKind | null,
): boolean {
  if (backendKind === null) {
    return false;
  }
  return getSyncBackendDescriptor(backendKind).configEditorKind === 'filesystem_root_path';
}

export function buildSyncBackendConfig(options: {
  backendKind: SyncBackendKind | null;
  backendConfigs: SyncBackendConfigs;
}): SyncBackendConfig | null {
  if (options.backendKind === null) {
    return null;
  }
  return {
    kind: SYNC_BACKEND_FILESYSTEM_BRIDGE,
    config: {
      rootPath: options.backendConfigs.filesystem_bridge.rootPath.trim(),
    },
  };
}
