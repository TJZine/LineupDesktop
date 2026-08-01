import { createHash } from 'node:crypto';
import type { platform as processPlatform } from 'node:process';

import {
  DESKTOP_AUDIO_OUTPUT_MAX_DEVICE_COUNT,
  sanitizeAudioOutputLabel,
  type DesktopAudioOutputDeviceId,
  type DesktopAudioOutputList,
  type DesktopAudioOutputRow,
} from '../../contracts/settings.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { NativePlayerHostPort } from '../player/nativePlayerHostPort.js';

const SYSTEM_DEFAULT_ROW = Object.freeze({
  kind: 'system-default',
  id: 'system-default',
  label: 'System default',
} as const);
const HASH_DOMAIN = 'lineup-desktop-audio-output-v1\0';
const MAX_NATIVE_OUTPUTS = DESKTOP_AUDIO_OUTPUT_MAX_DEVICE_COUNT;
type RuntimePlatform = typeof processPlatform;

export interface SettingsAudioOutputOwnerOptions {
  platform: RuntimePlatform;
  nativeHost: NativePlayerHostPort | null;
  createRequestId(prefix: string): string;
  diagnosticEventStore?: DiagnosticEventStore;
  createOpaqueId?: (nativeKey: string) => DesktopAudioOutputDeviceId;
}

export interface ResolvedAudioOutput {
  audioOutputNativeKey: string | null;
  matched: boolean;
}

export class SettingsAudioOutputOwner {
  readonly #platform: RuntimePlatform;
  readonly #nativeHost: NativePlayerHostPort | null;
  readonly #createRequestId: (prefix: string) => string;
  readonly #diagnosticEventStore?: DiagnosticEventStore;
  readonly #createOpaqueId: (nativeKey: string) => DesktopAudioOutputDeviceId;

  public constructor(options: SettingsAudioOutputOwnerOptions) {
    this.#platform = options.platform;
    this.#nativeHost = options.nativeHost;
    this.#createRequestId = options.createRequestId;
    this.#diagnosticEventStore = options.diagnosticEventStore;
    this.#createOpaqueId = options.createOpaqueId ?? createAudioOutputDeviceId;
  }

  public async getAudioOutputs(): Promise<DesktopAudioOutputList> {
    const enumeration = await this.#enumerate();
    return enumeration.publicList;
  }

  public async resolveSelectedOutput(
    selectedId: DesktopAudioOutputDeviceId | null,
  ): Promise<ResolvedAudioOutput> {
    if (selectedId === null) {
      return { audioOutputNativeKey: null, matched: true };
    }
    const enumeration = await this.#enumerate();
    const nativeKey = enumeration.nativeKeyById.get(selectedId) ?? null;
    if (nativeKey === null) {
      this.#recordFixedDiagnostic('audio-output-selection-unavailable', {
        retainedDeviceCount: Math.max(0, enumeration.publicList.outputs.length - 1),
      });
      return { audioOutputNativeKey: null, matched: false };
    }
    return { audioOutputNativeKey: nativeKey, matched: true };
  }

  async #enumerate(): Promise<{
    publicList: DesktopAudioOutputList;
    nativeKeyById: Map<DesktopAudioOutputDeviceId, string>;
  }> {
    if (this.#platform !== 'win32') {
      return unavailable('platform-unsupported');
    }
    if (this.#nativeHost === null) {
      return unavailable('helper-unavailable');
    }
    const result = await this.#nativeHost.queryAudioOutputs(
      this.#createRequestId('native-audio-output'),
    );
    if (!result.ok) {
      this.#recordFixedDiagnostic('audio-output-enumeration-failed');
      return unavailable('enumeration-failed');
    }

    const seenNativeKeys = new Set<string>();
    const nativeKeyById = new Map<DesktopAudioOutputDeviceId, string>();
    const rows: Array<{ row: Extract<DesktopAudioOutputRow, { kind: 'device' }>; nativeKey: string }> = [];
    let sanitized = false;
    for (const output of result.outputs) {
      if (seenNativeKeys.has(output.nativeKey)) {
        sanitized = true;
        continue;
      }
      seenNativeKeys.add(output.nativeKey);
      const label = sanitizeAudioOutputLabel(output.label);
      if (label === '') {
        sanitized = true;
        continue;
      }
      const id = this.#createOpaqueId(output.nativeKey);
      const existingNativeKey = nativeKeyById.get(id);
      if (existingNativeKey !== undefined && existingNativeKey !== output.nativeKey) {
        this.#recordFixedDiagnostic('audio-output-id-collision');
        return unavailable('enumeration-failed');
      }
      nativeKeyById.set(id, output.nativeKey);
      rows.push({ row: { kind: 'device', id, label }, nativeKey: output.nativeKey });
    }
    if (result.outputs.length > 0 && rows.length === 0) {
      this.#recordFixedDiagnostic('audio-output-enumeration-failed');
      return unavailable('enumeration-failed');
    }
    rows.sort((left, right) => (
      left.row.label < right.row.label ? -1 :
        left.row.label > right.row.label ? 1 :
          left.row.id < right.row.id ? -1 :
            left.row.id > right.row.id ? 1 : 0
    ));
    const truncated = rows.length > MAX_NATIVE_OUTPUTS;
    const retained = rows.slice(0, MAX_NATIVE_OUTPUTS);
    const retainedMap = new Map<DesktopAudioOutputDeviceId, string>(
      retained.map(({ row, nativeKey }) => [row.id, nativeKey]),
    );
    return {
      publicList: {
        status: sanitized || truncated ? 'partial' : 'ready',
        reason: sanitized
          ? 'device-list-sanitized'
          : truncated
            ? 'device-list-truncated'
            : 'available',
        outputs: [SYSTEM_DEFAULT_ROW, ...retained.map(({ row }) => row)],
      },
      nativeKeyById: retainedMap,
    };
  }

  #recordFixedDiagnostic(
    reason: 'audio-output-enumeration-failed' | 'audio-output-id-collision' | 'audio-output-selection-unavailable',
    context: Record<string, number> = {},
  ): void {
    this.#diagnosticEventStore?.record({
      surface: 'main',
      category: 'playback',
      severity: reason === 'audio-output-selection-unavailable' ? 'warning' : 'error',
      status: reason === 'audio-output-selection-unavailable' ? 'ignored' : 'failed',
      operation: 'settings.audio-output',
      message: 'Desktop audio output operation used a safe fallback.',
      result: reason === 'audio-output-selection-unavailable' ? 'ignored' : 'failure',
      context: { reason, ...context },
    });
  }
}

export function createAudioOutputDeviceId(nativeKey: string): DesktopAudioOutputDeviceId {
  const digest = createHash('sha256')
    .update(HASH_DOMAIN, 'utf8')
    .update(nativeKey, 'utf8')
    .digest('base64url');
  return `audio_${digest}`;
}

function unavailable(
  reason: 'platform-unsupported' | 'helper-unavailable' | 'enumeration-failed',
): {
  publicList: DesktopAudioOutputList;
  nativeKeyById: Map<DesktopAudioOutputDeviceId, string>;
} {
  return {
    publicList: { status: 'unavailable', reason, outputs: [SYSTEM_DEFAULT_ROW] },
    nativeKeyById: new Map(),
  };
}
