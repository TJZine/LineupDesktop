import type { platform as processPlatform } from 'node:process';

import {
  cloneDesktopSettingsCapabilities,
  cloneDesktopSettingsValues,
  createConservativeDesktopSettingsCapabilities,
  type DesktopSettingsCapabilityProjection,
  type DesktopSettingsSnapshot,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';
import type { DiagnosticEventInput } from '../diagnostics/diagnosticEventStore.js';

type RuntimePlatform = typeof processPlatform;

export interface DesktopSettingsDiagnosticAdmissionPort {
  setSettingsAdmission(input: {
    debugLoggingEnabled: boolean;
    subtitleDebugLoggingEnabled: boolean;
  }): void;
  recordSettingsDebug(input: DiagnosticEventInput): unknown;
}

export interface DesktopPlaybackSettingsPreferences {
  audioOutputDeviceId: DesktopSettingsValues['audioOutputDeviceId'];
  dtsPassthroughEnabled: boolean;
  directPlayAudioFallbackEnabled: boolean;
  subtitleMode: DesktopSettingsValues['subtitleMode'];
  preferredSubtitleLanguage: DesktopSettingsValues['preferredSubtitleLanguage'];
  preferForcedSubtitlesEnabled: boolean;
  hdrFallbackMode: DesktopSettingsValues['hdrFallbackMode'];
  transcodeQuality: DesktopSettingsValues['transcodeQuality'];
  transcodeCompatibilityModeEnabled: boolean;
}

export interface DesktopSettingsPolicyOptions {
  platform: RuntimePlatform;
  nativeHostAvailable: boolean;
  diagnosticAdmission?: DesktopSettingsDiagnosticAdmissionPort;
  capabilityProjection?: DesktopSettingsCapabilityProjection;
}

export class DesktopSettingsPolicy {
  readonly #platform: RuntimePlatform;
  readonly #nativeHostAvailable: boolean;
  readonly #diagnosticAdmission?: DesktopSettingsDiagnosticAdmissionPort;
  readonly #baseCapabilities: DesktopSettingsCapabilityProjection;
  #values: DesktopSettingsValues | null = null;

  public constructor(options: DesktopSettingsPolicyOptions) {
    this.#platform = options.platform;
    this.#nativeHostAvailable = options.nativeHostAvailable;
    this.#diagnosticAdmission = options.diagnosticAdmission;
    this.#baseCapabilities = cloneDesktopSettingsCapabilities(
      options.capabilityProjection ?? createConservativeDesktopSettingsCapabilities(),
    );
  }

  public acceptSnapshot(snapshot: DesktopSettingsSnapshot): void {
    this.#values = cloneDesktopSettingsValues(snapshot.values);
    try {
      this.#diagnosticAdmission?.setSettingsAdmission({
        debugLoggingEnabled: snapshot.values.debugLoggingEnabled,
        subtitleDebugLoggingEnabled: snapshot.values.subtitleDebugLoggingEnabled,
      });
      this.#diagnosticAdmission?.recordSettingsDebug({
        surface: 'main',
        category: 'lifecycle',
        severity: 'debug',
        status: 'observed',
        operation: 'settings.snapshot.accepted',
        message: 'Desktop settings snapshot accepted.',
        result: 'success',
        context: {
          revision: snapshot.revision,
          subtitleDebugLoggingEnabled: snapshot.values.subtitleDebugLoggingEnabled,
        },
      });
    } catch {
      // Best-effort diagnostics must not invalidate an accepted settings snapshot.
    }
  }

  public getPreferences(): DesktopPlaybackSettingsPreferences {
    if (this.#values === null) {
      throw new Error('Desktop settings policy has not been hydrated.');
    }
    return {
      audioOutputDeviceId: this.#values.audioOutputDeviceId,
      dtsPassthroughEnabled: this.#values.dtsPassthroughEnabled,
      directPlayAudioFallbackEnabled: this.#values.directPlayAudioFallbackEnabled,
      subtitleMode: this.#values.subtitleMode,
      preferredSubtitleLanguage: this.#values.preferredSubtitleLanguage,
      preferForcedSubtitlesEnabled: this.#values.preferForcedSubtitlesEnabled,
      hdrFallbackMode: this.#values.hdrFallbackMode,
      transcodeQuality: this.#values.transcodeQuality,
      transcodeCompatibilityModeEnabled: this.#values.transcodeCompatibilityModeEnabled,
    };
  }

  public getCapabilityProjection(): DesktopSettingsCapabilityProjection {
    const capabilities = cloneDesktopSettingsCapabilities(this.#baseCapabilities);
    if (this.#platform !== 'win32') {
      capabilities.audioOutputSelection = {
        status: 'unsupported',
        reason: 'platform-unsupported',
      };
    } else if (!this.#nativeHostAvailable) {
      capabilities.audioOutputSelection = {
        status: 'unsupported',
        reason: 'helper-unavailable',
      };
    }
    return capabilities;
  }
}
