import {
  buildRuntimeProfile,
  detectDesktopPlatform,
  detectMobilePlatform,
  resolveRuntimeId,
  type DesktopPlatform,
  type MobilePlatform,
  type RuntimeId,
  type RuntimeProfile,
} from './platform.logic';
import { readRuntimeNavigatorSnapshot } from './platform.runtime';

export type {
  DesktopPlatform,
  MobilePlatform,
  NativeCalendarActivationState,
  NativeCalendarAdapterKind,
  RuntimeId,
  RuntimeProfile,
  RuntimeClass,
  TrayPresentationKind,
} from './platform.logic';

const runtimeProfileCache = new Map<RuntimeId, RuntimeProfile>();

export function getDesktopPlatform(): DesktopPlatform {
  return detectDesktopPlatform(readRuntimeNavigatorSnapshot());
}

export function isMacRuntime(): boolean {
  const runtimeId = getRuntimeId();
  return runtimeId === 'macos';
}

export function getRuntimeId(): RuntimeId {
  return resolveRuntimeId(readRuntimeNavigatorSnapshot());
}

export function getRuntimeProfile(): RuntimeProfile {
  const runtimeId = getRuntimeId();
  const cached = runtimeProfileCache.get(runtimeId);
  if (cached) return cached;
  const profile = buildRuntimeProfile(runtimeId);
  runtimeProfileCache.set(runtimeId, profile);
  return profile;
}

export function getMobilePlatform(): MobilePlatform {
  return detectMobilePlatform(readRuntimeNavigatorSnapshot());
}

export function getRuntimeUserAgentSnippet(maxLength = 200): string {
  return readRuntimeNavigatorSnapshot()?.userAgent.slice(0, maxLength) ?? 'unknown';
}
