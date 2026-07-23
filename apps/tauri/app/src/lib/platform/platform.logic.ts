import { SYNC_BACKEND_FILESYSTEM_BRIDGE, type SyncBackendKind } from '../syncBackend/kinds.ts';

export type DesktopPlatform = 'macos' | 'windows' | 'linux' | 'unknown';
export type MobilePlatform = 'android' | 'unknown';
export type RuntimeClass = 'desktop' | 'mobile' | 'unknown';
export type RuntimeId = 'macos' | 'windows' | 'linux' | 'android' | 'unknown';
export type TrayPresentationKind = 'none' | 'menu_bar' | 'system_tray';
export type NativeCalendarAdapterKind =
  | 'none'
  | 'windows_appointments'
  | 'linux_ics';
export type NativeCalendarActivationState = 'active' | 'planned' | 'none';

interface RuntimeProfileDefinition {
  runtimeClass: RuntimeClass;
  supportsBiometricLock: boolean;
  supportsMultipleWindows: boolean;
  supportsTitleBarOverlay: boolean;
  supportsMcpHosting: boolean;
  supportedSyncBackendKinds: readonly SyncBackendKind[];
  trayPresentationKind: TrayPresentationKind;
  supportsDesktopOverlays: boolean;
  supportsAssistantCommandPolling: boolean;
  supportsAutostart: boolean;
  supportsNativeCalendarRead: boolean;
  supportsBackgroundSync: boolean;
  biometricAdapterKind: 'none' | 'touch_id' | 'windows_hello';
  nativeCalendarAdapterKind: NativeCalendarAdapterKind;
  nativeCalendarActivationState: NativeCalendarActivationState;
}

export interface RuntimeProfile {
  runtimeId: RuntimeId;
  runtimeClass: RuntimeClass;
  supportsBiometricLock: boolean;
  supportsMultipleWindows: boolean;
  supportsTitleBarOverlay: boolean;
  supportsMcpHosting: boolean;
  supportedSyncBackendKinds: readonly SyncBackendKind[];
  trayPresentationKind: TrayPresentationKind;
  supportsDesktopOverlays: boolean;
  supportsAssistantCommandPolling: boolean;
  supportsAutostart: boolean;
  supportsNativeCalendarRead: boolean;
  supportsBackgroundSync: boolean;
  biometricAdapterKind: 'none' | 'touch_id' | 'windows_hello';
  nativeCalendarAdapterKind: NativeCalendarAdapterKind;
  nativeCalendarActivationState: NativeCalendarActivationState;
}

export interface RuntimeNavigatorSnapshot {
  userAgent: string;
  maxTouchPoints: number;
}

const UNKNOWN_RUNTIME_PROFILE: RuntimeProfileDefinition = {
  runtimeClass: 'unknown',
  supportsBiometricLock: false,
  supportsMultipleWindows: false,
  supportsTitleBarOverlay: false,
  supportsMcpHosting: false,
  supportedSyncBackendKinds: [],
  trayPresentationKind: 'none',
  supportsDesktopOverlays: false,
  supportsAssistantCommandPolling: false,
  supportsAutostart: false,
  supportsNativeCalendarRead: false,
  supportsBackgroundSync: false,
  biometricAdapterKind: 'none',
  nativeCalendarAdapterKind: 'none',
  nativeCalendarActivationState: 'none',
};

const RUNTIME_PROFILE_DEFINITIONS: Record<Exclude<RuntimeId, 'unknown'>, RuntimeProfileDefinition> = {
  macos: {
    runtimeClass: 'desktop',
    supportsBiometricLock: true,
    supportsMultipleWindows: true,
    supportsTitleBarOverlay: true,
    supportsMcpHosting: true,
    supportedSyncBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    trayPresentationKind: 'menu_bar',
    supportsDesktopOverlays: true,
    supportsAssistantCommandPolling: true,
    supportsAutostart: true,
    supportsNativeCalendarRead: false,
    supportsBackgroundSync: true,
    biometricAdapterKind: 'touch_id',
    nativeCalendarAdapterKind: 'none',
    nativeCalendarActivationState: 'none',
  },
  windows: {
    runtimeClass: 'desktop',
    supportsBiometricLock: true,
    supportsMultipleWindows: true,
    supportsTitleBarOverlay: false,
    supportsMcpHosting: true,
    // A future Windows-native sync transport (OneDrive folder helper,
    // SMB-aware filesystem bridge variant, etc.) would land as an
    // additional entry in this array.
    supportedSyncBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    trayPresentationKind: 'system_tray',
    supportsDesktopOverlays: true,
    supportsAssistantCommandPolling: true,
    supportsAutostart: true,
    supportsNativeCalendarRead: true,
    supportsBackgroundSync: true,
    biometricAdapterKind: 'windows_hello',
    nativeCalendarAdapterKind: 'windows_appointments',
    nativeCalendarActivationState: 'active',
  },
  linux: {
    runtimeClass: 'desktop',
    supportsBiometricLock: false,
    supportsMultipleWindows: true,
    supportsTitleBarOverlay: false,
    supportsMcpHosting: true,
    supportedSyncBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    trayPresentationKind: 'system_tray',
    supportsDesktopOverlays: true,
    supportsAssistantCommandPolling: true,
    supportsAutostart: true,
    supportsNativeCalendarRead: true,
    supportsBackgroundSync: true,
    biometricAdapterKind: 'none',
    nativeCalendarAdapterKind: 'linux_ics',
    nativeCalendarActivationState: 'active',
  },
  android: {
    runtimeClass: 'mobile',
    supportsBiometricLock: false,
    supportsMultipleWindows: false,
    supportsTitleBarOverlay: false,
    supportsMcpHosting: false,
    supportedSyncBackendKinds: [],
    trayPresentationKind: 'none',
    supportsDesktopOverlays: false,
    supportsAssistantCommandPolling: false,
    supportsAutostart: false,
    supportsNativeCalendarRead: false,
    supportsBackgroundSync: false,
    biometricAdapterKind: 'none',
    nativeCalendarAdapterKind: 'none',
    nativeCalendarActivationState: 'none',
  },
};

export function detectMobilePlatform(snapshot: RuntimeNavigatorSnapshot | null): MobilePlatform {
  if (!snapshot) {
    return 'unknown';
  }

  const ua = snapshot.userAgent.toLowerCase();

  if (ua.includes('android')) {
    return 'android';
  }

  return 'unknown';
}

export function detectDesktopPlatform(snapshot: RuntimeNavigatorSnapshot | null): DesktopPlatform {
  if (!snapshot) {
    return 'unknown';
  }
  if (detectMobilePlatform(snapshot) !== 'unknown') {
    return 'unknown';
  }

  const ua = snapshot.userAgent.toLowerCase();
  if (ua.includes('windows')) {
    return 'windows';
  }
  if (ua.includes('macintosh') || ua.includes('mac os x')) {
    return 'macos';
  }
  if (ua.includes('linux') || ua.includes('x11')) {
    return 'linux';
  }

  return 'unknown';
}

export function resolveRuntimeId(snapshot: RuntimeNavigatorSnapshot | null): RuntimeId {
  const mobilePlatform = detectMobilePlatform(snapshot);
  if (mobilePlatform !== 'unknown') {
    return mobilePlatform;
  }
  return detectDesktopPlatform(snapshot);
}

export function buildRuntimeProfile(runtimeId: RuntimeId): RuntimeProfile {
  const definition = runtimeId === 'unknown'
    ? UNKNOWN_RUNTIME_PROFILE
    : RUNTIME_PROFILE_DEFINITIONS[runtimeId];

  return {
    runtimeId,
    runtimeClass: definition.runtimeClass,
    supportsBiometricLock: definition.supportsBiometricLock,
    supportsMultipleWindows: definition.supportsMultipleWindows,
    supportsTitleBarOverlay: definition.supportsTitleBarOverlay,
    supportsMcpHosting: definition.supportsMcpHosting,
    supportedSyncBackendKinds: definition.supportedSyncBackendKinds,
    trayPresentationKind: definition.trayPresentationKind,
    supportsDesktopOverlays: definition.supportsDesktopOverlays,
    supportsAssistantCommandPolling: definition.supportsAssistantCommandPolling,
    supportsAutostart: definition.supportsAutostart,
    supportsNativeCalendarRead: definition.supportsNativeCalendarRead,
    supportsBackgroundSync: definition.supportsBackgroundSync,
    biometricAdapterKind: definition.biometricAdapterKind,
    nativeCalendarAdapterKind: definition.nativeCalendarAdapterKind,
    nativeCalendarActivationState: definition.nativeCalendarActivationState,
  };
}

export function getClaudeDesktopConfigPathHintForRuntime(runtimeId: RuntimeId): string {
  if (runtimeId === 'windows') {
    return '%APPDATA%\\Claude\\claude_desktop_config.json';
  }
  if (runtimeId === 'linux') {
    return '~/.config/Claude/claude_desktop_config.json';
  }
  return '~/Library/Application Support/Claude/claude_desktop_config.json';
}

export function getClaudeCodeConfigPathHintForRuntime(runtimeId: RuntimeId): string {
  if (runtimeId === 'windows') {
    return '%USERPROFILE%\\.claude.json';
  }
  return '~/.claude.json';
}

export function getCodexConfigPathHintForRuntime(runtimeId: RuntimeId): string {
  if (runtimeId === 'windows') {
    return '%USERPROFILE%\\.codex\\config.toml';
  }
  return '~/.codex/config.toml';
}
