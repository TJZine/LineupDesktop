import type { PlayerRendererIntentEnvelope, RendererIntentEnvelope } from './ipc.js';
import type {
  ChannelSetupAcceptedOperation,
  ChannelSetupCancelResult,
  ChannelSetupConfig,
  ChannelSetupIpcResult,
  ChannelSetupOperationResult,
  ChannelSetupSummary,
} from './channel.js';
import type {
  DiagnosticsExportSupportBundleResult,
  DiagnosticsGetSummaryResult,
  DiagnosticsRecordRendererEventResult,
  DiagnosticsRendererEventEnvelope,
} from './diagnostics.js';
import type {
  PlayerDispatchResult,
  PlayerError,
  PlayerEvent,
  PlayerIpcResult,
  PlayerSnapshot,
} from './player.js';
import type {
  EpgPresentationSource,
  GuideIpcResult,
} from './guide.js';
import type {
  PlexCancelPinValue,
  PlexGetHomeUsersValue,
  PlexGetMetadataValue,
  PlexIpcResult,
  PlexListLibraryItemsValue,
  PlexListLibrarySectionsValue,
  PlexPollPinValue,
  PlexRefreshServersValue,
  PlexRequestPinValue,
  PlexRestoreSelectedServerValue,
  PlexRendererMediaType,
  PlexRuntimeSnapshot,
  PlexSearchLibraryValue,
  PlexSelectServerValue,
  PlexSwitchHomeUserValue,
} from './plex.js';
import type {
  CustomChannelDeleteRequest,
  CustomChannelDraftInput,
  CustomChannelDraftResult,
  CustomChannelDraftValidationSummary,
  CustomChannelDuplicateDraftRequest,
  CustomChannelGetMediaMetadataRequest,
  CustomChannelIpcResult,
  CustomChannelListMediaRequest,
  CustomChannelMediaMetadata,
  CustomChannelMediaPage,
  CustomChannelMutationResult,
  CustomChannelReorderRequest,
  CustomChannelSnapshot,
  CustomChannelVisibilityRequest,
} from './customChannels.js';
import type {
  DesktopAudioOutputList,
  DesktopSettingsGetAudioOutputsRequest,
  DesktopSettingsGetSnapshotRequest,
  DesktopSettingsIpcResult,
  DesktopSettingsReplaceRequest,
  DesktopSettingsView,
} from './settings.js';

export const LINEUP_PROTOCOL_ORIGIN = 'lineup://shell' as const;
export const LINEUP_SHELL_URL = 'lineup://shell/index.html' as const;
export const LINEUP_APP_NAME = 'Lineup Desktop' as const;

export const SHELL_CAPABILITY_PLATFORMS = ['darwin', 'linux', 'win32', 'unknown'] as const;
export const SHELL_MODES = ['development', 'smoke', 'production'] as const;
export const SHELL_STATUS_VALUES = ['booting', 'ready', 'closing'] as const;
export const SHELL_ERROR_CODES = [
  'unauthorized',
  'validation-failed',
  'operation-failed',
] as const;

export type ShellCapabilityPlatform = (typeof SHELL_CAPABILITY_PLATFORMS)[number];
export type ShellMode = (typeof SHELL_MODES)[number];
export type ShellStatusValue = (typeof SHELL_STATUS_VALUES)[number];
export type ShellErrorCode = (typeof SHELL_ERROR_CODES)[number];

export interface ShellCapabilities {
  appName: typeof LINEUP_APP_NAME;
  appVersion: string;
  platform: ShellCapabilityPlatform;
  shellMode: ShellMode;
  protocolOrigin: typeof LINEUP_PROTOCOL_ORIGIN;
}

export interface ShellStatusEvent {
  status: ShellStatusValue;
  timestampMs: number;
}

export interface WindowFullscreenState {
  enabled: boolean;
}

export type ShellIpcResult<T> =
  | { ok: true; value: T; requestId: string }
  | {
      ok: false;
      error: { code: ShellErrorCode; message: string };
      requestId: string;
    };

export type WindowFullscreenIntentEnvelope = RendererIntentEnvelope<Record<string, never>> & {
  intent: 'window.enterFullscreen' | 'window.exitFullscreen';
};

export const PLAYER_RECOVERY_ACTIONS = ['retry-current', 'skip-next'] as const;
export type PlayerRecoveryAction = (typeof PLAYER_RECOVERY_ACTIONS)[number];

export type PlayerRecoveryIpcResult =
  | {
      ok: true;
      requestId: string;
      value: {
        status: 'accepted';
        snapshot: PlayerSnapshot;
      };
    }
  | {
      ok: false;
      requestId: string;
      value: {
        status: 'failed';
        snapshot: PlayerSnapshot;
      };
      error: PlayerError;
    };

/**
 * This is the narrow renderer-facing bridge contract exposed by preload.
 * Invoke methods return typed result envelopes expected from authorized main
 * handlers; event subscriptions return an unsubscribe function.
 */
export interface LineupDesktopPreloadApi {
  shell: {
    getCapabilities: () => Promise<ShellIpcResult<ShellCapabilities>>;
    onStatusChanged: (listener: (event: ShellStatusEvent) => void) => () => void;
  };
  window: {
    setFullscreen: (
      enabled: boolean,
    ) => Promise<ShellIpcResult<WindowFullscreenState>>;
  };
  settings: {
    getSnapshot: (
      input: DesktopSettingsGetSnapshotRequest,
    ) => Promise<DesktopSettingsIpcResult<DesktopSettingsView>>;
    replace: (
      input: DesktopSettingsReplaceRequest,
    ) => Promise<DesktopSettingsIpcResult<DesktopSettingsView>>;
    getAudioOutputs: (
      input: DesktopSettingsGetAudioOutputsRequest,
    ) => Promise<DesktopSettingsIpcResult<DesktopAudioOutputList>>;
  };
  player: {
    dispatch: (
      envelope: PlayerRendererIntentEnvelope<unknown>,
    ) => Promise<PlayerIpcResult<PlayerDispatchResult>>;
    getSnapshot: () => Promise<PlayerIpcResult<PlayerSnapshot>>;
    cleanup: () => Promise<PlayerIpcResult<PlayerSnapshot>>;
    tuneChannel: (input: { channelId: string }) => Promise<GuideIpcResult<never>>;
    recover: (input: { action: PlayerRecoveryAction }) => Promise<PlayerRecoveryIpcResult>;
    onEvent: (listener: (event: PlayerEvent) => void) => () => void;
  };
  diagnostics: {
    recordRendererEvent: (
      envelope: DiagnosticsRendererEventEnvelope,
    ) => Promise<DiagnosticsRecordRendererEventResult>;
    getSummary: () => Promise<DiagnosticsGetSummaryResult>;
    exportSupportBundle: () => Promise<DiagnosticsExportSupportBundleResult>;
  };
  plex: {
    getSnapshot: () => Promise<PlexIpcResult<PlexRuntimeSnapshot>>;
    requestPin: () => Promise<PlexIpcResult<PlexRequestPinValue>>;
    pollPin: (input: { pinId: number }) => Promise<PlexIpcResult<PlexPollPinValue>>;
    cancelPin: (input: { pinId: number }) => Promise<PlexIpcResult<PlexCancelPinValue>>;
    getHomeUsers: () => Promise<PlexIpcResult<PlexGetHomeUsersValue>>;
    switchHomeUser: (input: {
      userId: string;
      pin?: string | null;
    }) => Promise<PlexIpcResult<PlexSwitchHomeUserValue>>;
    restoreSelectedServer: () => Promise<PlexIpcResult<PlexRestoreSelectedServerValue>>;
    refreshServers: () => Promise<PlexIpcResult<PlexRefreshServersValue>>;
    selectServer: (input: {
      serverId: string;
    }) => Promise<PlexIpcResult<PlexSelectServerValue>>;
    listLibrarySections: () => Promise<PlexIpcResult<PlexListLibrarySectionsValue>>;
    listLibraryItems: (input: {
      sectionId: string;
      offset?: number;
      limit?: number;
      sort?: string;
      filter?: Readonly<Record<string, string | number>>;
      includeCollections?: boolean;
    }) => Promise<PlexIpcResult<PlexListLibraryItemsValue>>;
    searchLibrary: (input: {
      query: string;
      sectionId?: string;
      limit?: number;
      types?: readonly PlexRendererMediaType[];
    }) => Promise<PlexIpcResult<PlexSearchLibraryValue>>;
    getMetadata: (input: {
      ratingKey: string;
    }) => Promise<PlexIpcResult<PlexGetMetadataValue>>;
  };
  channelSetup: {
    getStatus: () => Promise<ChannelSetupIpcResult<ChannelSetupSummary>>;
    startReview: (
      input: { config: ChannelSetupConfig },
    ) => Promise<ChannelSetupIpcResult<ChannelSetupAcceptedOperation>>;
    startApply: (
      input: { planId: string; confirmReplace: boolean },
    ) => Promise<ChannelSetupIpcResult<ChannelSetupAcceptedOperation>>;
    getOperation: (
      input: { operationId: string },
    ) => Promise<ChannelSetupIpcResult<ChannelSetupOperationResult>>;
    cancel: (
      input: { operationId: string },
    ) => Promise<ChannelSetupIpcResult<ChannelSetupCancelResult>>;
  };
  customChannels: {
    getSnapshot: () => Promise<CustomChannelIpcResult<CustomChannelSnapshot>>;
    listMedia: (
      input: CustomChannelListMediaRequest['payload'],
    ) => Promise<CustomChannelIpcResult<CustomChannelMediaPage>>;
    getMediaMetadata: (
      input: CustomChannelGetMediaMetadataRequest['payload'],
    ) => Promise<CustomChannelIpcResult<CustomChannelMediaMetadata>>;
    validateDraft: (
      input: CustomChannelDraftInput,
    ) => Promise<CustomChannelIpcResult<CustomChannelDraftValidationSummary>>;
    saveDraft: (
      input: CustomChannelDraftInput,
    ) => Promise<CustomChannelIpcResult<CustomChannelMutationResult>>;
    deleteChannel: (
      input: CustomChannelDeleteRequest['payload'],
    ) => Promise<CustomChannelIpcResult<CustomChannelMutationResult>>;
    duplicateChannelDraft: (
      input: CustomChannelDuplicateDraftRequest['payload'],
    ) => Promise<CustomChannelIpcResult<CustomChannelDraftResult>>;
    reorderChannels: (
      input: CustomChannelReorderRequest['payload'],
    ) => Promise<CustomChannelIpcResult<CustomChannelMutationResult>>;
    setChannelVisibility: (
      input: CustomChannelVisibilityRequest['payload'],
    ) => Promise<CustomChannelIpcResult<CustomChannelMutationResult>>;
  };
  guide: {
    getPresentation: (input: {
      startTimeMs: number;
      durationMs: number;
    }) => Promise<GuideIpcResult<EpgPresentationSource>>;
  };
}

export function isShellStatusEvent(value: unknown): value is ShellStatusEvent {
  if (!isPlainRecord(value)) {
    return false;
  }
  return (
    typeof value.timestampMs === 'number' &&
    Number.isFinite(value.timestampMs) &&
    SHELL_STATUS_VALUES.includes(value.status as ShellStatusValue)
  );
}

export function isWindowFullscreenIntentEnvelope(
  value: unknown,
): value is WindowFullscreenIntentEnvelope {
  if (!isPlainRecord(value) || typeof value.requestId !== 'string') {
    return false;
  }
  if (
    value.intent !== 'window.enterFullscreen' &&
    value.intent !== 'window.exitFullscreen'
  ) {
    return false;
  }
  if (!isPlainRecord(value.payload)) {
    return false;
  }
  return Object.keys(value.payload).length === 0;
}

export function shellSuccess<T>(requestId: string, value: T): ShellIpcResult<T> {
  return { ok: true, value, requestId };
}

export function shellFailure<T>(
  requestId: string,
  code: ShellErrorCode,
  message: string,
): ShellIpcResult<T> {
  return { ok: false, error: { code, message }, requestId };
}

export function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}
