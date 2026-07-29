import type { platform as processPlatform } from 'node:process';

import type { ShellMode } from '../../contracts/shell.js';
import type { DesktopSettingsSnapshot } from '../../contracts/settings.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { NativePlayerHostPort } from '../player/nativePlayerHostPort.js';
import { DesktopSettingsPolicy } from './desktopSettingsPolicy.js';
import { SettingsAudioOutputOwner } from './settingsAudioOutputOwner.js';

type RuntimePlatform = typeof processPlatform;

export interface SettingsNativeHostCompositionOptions {
  shellMode: ShellMode;
  platform: RuntimePlatform;
  initialSnapshot: DesktopSettingsSnapshot;
  createProductionNativeHost(): NativePlayerHostPort | null;
  createRequestId(prefix: string): string;
  diagnosticEventStore: DiagnosticEventStore;
}

export interface SettingsNativeHostComposition {
  nativeHost: NativePlayerHostPort | null;
  settingsPolicy: DesktopSettingsPolicy;
  settingsAudioOutputOwner: SettingsAudioOutputOwner;
}

export function createSettingsNativeHostComposition(
  options: SettingsNativeHostCompositionOptions,
): SettingsNativeHostComposition {
  const nativeHost = options.shellMode === 'production'
    ? options.createProductionNativeHost()
    : null;
  const settingsPolicy = new DesktopSettingsPolicy({
    platform: options.platform,
    nativeHostAvailable: nativeHost !== null,
    diagnosticAdmission: options.diagnosticEventStore,
  });
  settingsPolicy.acceptSnapshot(options.initialSnapshot);

  return {
    nativeHost,
    settingsPolicy,
    settingsAudioOutputOwner: new SettingsAudioOutputOwner({
      platform: options.platform,
      nativeHost,
      createRequestId: options.createRequestId,
      diagnosticEventStore: options.diagnosticEventStore,
    }),
  };
}
