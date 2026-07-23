import {
  createDefaultSyncBackendConfigs,
  resolveSyncBackend,
  type SyncBackendConfigs,
  type SyncBackendSettings,
  type SyncBackendSupportContext,
} from './model.ts';
import type { SyncBackendKind } from './kinds.ts';
import { parseBooleanPreference, tryParsePreferenceJson } from '../preferences/parser';
import { hasOnlyKeys, isPlainRecord as isRecord } from '../objectGuards';

interface StoredSyncBackendKindPreferenceState {
  configuredBackendKind: SyncBackendKind | null;
  effectiveBackendKind: SyncBackendKind | null;
  malformed: boolean;
  malformedReason: string | null;
}

interface StoredSyncBackendConfigsPreferenceState {
  backendConfigs: SyncBackendConfigs;
  malformed: boolean;
  missingFilesystemRootPath: boolean;
}

function coerceStoredSyncBackendKind(candidate: unknown): SyncBackendKind | null {
  if (typeof candidate !== 'string' || !candidate.trim()) {
    return null;
  }
  const value = candidate.trim();
  if (value === 'filesystem_bridge') {
    return value as SyncBackendKind;
  }
  return null;
}

const SYNC_BACKEND_CONFIG_KEYS = new Set(['filesystem_bridge']);
const FILESYSTEM_BRIDGE_CONFIG_KEYS = new Set(['rootPath']);

function parseRequestedSyncBackendKindRaw(raw: string | null): {
  configuredBackendKind: SyncBackendKind | null;
  malformed: boolean;
  malformedReason: string | null;
} {
  if (raw === null) {
    return {
      configuredBackendKind: null,
      malformed: false,
      malformedReason: null,
    };
  }

  const parsed = tryParsePreferenceJson(raw);
  if (!parsed.ok) {
    return {
      configuredBackendKind: null,
      malformed: true,
      malformedReason: 'invalid_json',
    };
  }

  if (parsed.value === null) {
    return {
      configuredBackendKind: null,
      malformed: false,
      malformedReason: null,
    };
  }

  const configuredBackendKind = coerceStoredSyncBackendKind(parsed.value);
  if (configuredBackendKind !== null) {
    return {
      configuredBackendKind,
      malformed: false,
      malformedReason: null,
    };
  }

  if (typeof parsed.value === 'string') {
    return {
      configuredBackendKind: null,
      malformed: true,
      malformedReason: 'unknown_backend_kind',
    };
  }

  return {
    configuredBackendKind: null,
    malformed: true,
    malformedReason: 'invalid_backend_kind',
  };
}

export function parseStoredSyncEnabledPreference(raw: string | null): boolean {
  return parseBooleanPreference(raw, false);
}

export function parseStoredSyncBackendKindPreference(
  raw: string | null,
  options: SyncBackendSupportContext,
): SyncBackendKind | null {
  return parseStoredSyncBackendKindPreferenceState(raw, options).effectiveBackendKind;
}

export function parseStoredSyncBackendKindPreferenceState(
  raw: string | null,
  options: SyncBackendSupportContext,
): StoredSyncBackendKindPreferenceState {
  const parsed = parseRequestedSyncBackendKindRaw(raw);
  const resolvedBackend = resolveSyncBackend({
    requestedBackendKindRaw: parsed.configuredBackendKind,
    ...options,
  });

  return {
    configuredBackendKind: parsed.configuredBackendKind,
    effectiveBackendKind: resolvedBackend.effectiveBackendKind,
    malformed: parsed.malformed,
    malformedReason: parsed.malformedReason,
  };
}

export function parseStoredSyncBackendConfigsPreference(raw: string | null): SyncBackendConfigs {
  return parseStoredSyncBackendConfigsPreferenceState(raw).backendConfigs;
}

export function parseStoredSyncBackendConfigsPreferenceState(
  raw: string | null,
): StoredSyncBackendConfigsPreferenceState {
  const defaults = createDefaultSyncBackendConfigs();
  if (raw === null) {
    return {
      backendConfigs: defaults,
      malformed: false,
      missingFilesystemRootPath: true,
    };
  }

  const parsed = tryParsePreferenceJson(raw);
  if (!parsed.ok) {
    return {
      backendConfigs: defaults,
      malformed: true,
      missingFilesystemRootPath: true,
    };
  }

  if (!isRecord(parsed.value) || !hasOnlyKeys(parsed.value, SYNC_BACKEND_CONFIG_KEYS)) {
    return {
      backendConfigs: defaults,
      malformed: true,
      missingFilesystemRootPath: true,
    };
  }

  const record = parsed.value;
  const filesystemBridge = record.filesystem_bridge;
  const hasFilesystemBridgeObject =
    isRecord(filesystemBridge)
    && hasOnlyKeys(filesystemBridge, FILESYSTEM_BRIDGE_CONFIG_KEYS);
  const rootPathRaw = hasFilesystemBridgeObject ? filesystemBridge.rootPath : null;
  const hasFilesystemRootPath = typeof rootPathRaw === 'string';
  const rootPath = hasFilesystemRootPath
    ? rootPathRaw.trim()
    : '';

  return {
    backendConfigs: {
      filesystem_bridge: {
        rootPath,
      },
    },
    malformed: !hasFilesystemRootPath,
    missingFilesystemRootPath: !rootPath,
  };
}

export function resolveStoredSyncBackendSettings(options: {
  enabledRaw: string | null;
  backendKindRaw: string | null;
  backendConfigsRaw: string | null;
  defaultFilesystemBridgeRootPath: string | null;
  syncBackendSupport: SyncBackendSupportContext;
}): {
  settings: SyncBackendSettings;
  shouldPersistNormalized: boolean;
} {
  const requestedEnabled = parseStoredSyncEnabledPreference(options.enabledRaw);
  const backendKindState = parseStoredSyncBackendKindPreferenceState(
    options.backendKindRaw,
    options.syncBackendSupport,
  );
  const enabled = requestedEnabled && backendKindState.effectiveBackendKind !== null;
  const backendConfigsState = parseStoredSyncBackendConfigsPreferenceState(options.backendConfigsRaw);
  const backendConfigs = backendConfigsState.backendConfigs;

  const normalizedRootPath = options.defaultFilesystemBridgeRootPath?.trim() ?? '';
  const needsDefaultFilesystemBridgeRootPath = Boolean(
    normalizedRootPath
    && backendKindState.effectiveBackendKind === 'filesystem_bridge'
    && backendConfigsState.missingFilesystemRootPath,
  );
  const normalizedBackendConfigs = needsDefaultFilesystemBridgeRootPath
    ? {
      ...backendConfigs,
      filesystem_bridge: {
        rootPath: normalizedRootPath,
      },
    }
    : backendConfigs;

  return {
    settings: {
      enabled,
      configuredBackendKind: backendKindState.configuredBackendKind,
      effectiveBackendKind: backendKindState.effectiveBackendKind,
      backendConfigs: normalizedBackendConfigs,
    },
    shouldPersistNormalized: needsDefaultFilesystemBridgeRootPath || backendConfigsState.malformed,
  };
}
