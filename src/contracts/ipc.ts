export type DesktopIpcOwner = 'renderer' | 'preload' | 'main' | 'native-helper';

export type RendererIntent =
  | 'player.load'
  | 'player.play'
  | 'player.playIfCurrent'
  | 'player.pause'
  | 'player.pauseIfCurrent'
  | 'player.stop'
  | 'player.stopIfCurrent'
  | 'player.seekAbsolute'
  | 'player.seekRelative'
  | 'player.seekRelativeIfCurrent'
  | 'player.setVolume'
  | 'player.setMute'
  | 'player.selectAudio'
  | 'player.selectSubtitle'
  | 'window.enterFullscreen'
  | 'window.exitFullscreen';

type RendererPlayerIntent = Extract<RendererIntent, `player.${string}`>;
type IsExactUnion<TActual, TExpected> =
  [TActual] extends [TExpected] ? ([TExpected] extends [TActual] ? true : false) : false;
type AssertTrue<TValue extends true> = TValue;

export const PLAYER_RENDERER_INTENTS = [
  'player.load',
  'player.play',
  'player.playIfCurrent',
  'player.pause',
  'player.pauseIfCurrent',
  'player.stop',
  'player.stopIfCurrent',
  'player.seekAbsolute',
  'player.seekRelative',
  'player.seekRelativeIfCurrent',
  'player.setVolume',
  'player.setMute',
  'player.selectAudio',
  'player.selectSubtitle',
] as const satisfies readonly RendererPlayerIntent[];

export type PlayerRendererIntent = (typeof PLAYER_RENDERER_INTENTS)[number];

export type PlayerRendererIntentCoverage = AssertTrue<
  IsExactUnion<PlayerRendererIntent, RendererPlayerIntent>
>;

/**
 * Renderer intent envelopes are the shared renderer-to-main command shape;
 * additions must be reviewed as cross-process payload surface, not local UI
 * data.
 */
export interface RendererIntentEnvelope<TPayload = unknown> {
  intent: RendererIntent;
  requestId: string;
  payload: TPayload;
}

export type PlayerRendererIntentEnvelope<TPayload = unknown> =
  RendererIntentEnvelope<TPayload> & {
    intent: PlayerRendererIntent;
  };

export const LINEUP_SHELL_GET_CAPABILITIES_CHANNEL =
  'lineup:shell:getCapabilities' as const;

export const LINEUP_WINDOW_INTENT_CHANNEL = 'lineup:window:intent' as const;

export const LINEUP_SHELL_STATUS_CHANGED_CHANNEL =
  'lineup:shell:statusChanged' as const;

export const LINEUP_SHELL_MEDIA_INPUT_CHANNEL =
  'lineup:shell:mediaInput' as const;

export const LINEUP_PLAYER_COMMAND_CHANNEL = 'lineup:player:command' as const;

export const LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL =
  'lineup:player:getSnapshot' as const;

export const LINEUP_PLAYER_CLEANUP_CHANNEL = 'lineup:player:cleanup' as const;

export const LINEUP_PLAYER_EVENT_CHANNEL = 'lineup:player:event' as const;

export const LINEUP_PLAYER_UPDATE_PRESENTATION_CHANNEL =
  'lineup:player:updatePresentation' as const;

export const LINEUP_PLAYER_RECOVERY_CHANNEL = 'lineup:player:recovery' as const;

export const LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL =
  'lineup:diagnostics:recordRendererEvent' as const;

export const LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL =
  'lineup:diagnostics:getSummary' as const;

export const LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL =
  'lineup:diagnostics:exportSupportBundle' as const;

export const LINEUP_PLEX_GET_SNAPSHOT_CHANNEL =
  'lineup:plex:getSnapshot' as const;

export const LINEUP_PLEX_REQUEST_PIN_CHANNEL =
  'lineup:plex:requestPin' as const;

export const LINEUP_PLEX_POLL_PIN_CHANNEL = 'lineup:plex:pollPin' as const;

export const LINEUP_PLEX_CANCEL_PIN_CHANNEL = 'lineup:plex:cancelPin' as const;

export const LINEUP_PLEX_GET_HOME_USERS_CHANNEL =
  'lineup:plex:getHomeUsers' as const;

export const LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL =
  'lineup:plex:switchHomeUser' as const;

export const LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL =
  'lineup:plex:restoreSelectedServer' as const;

export const LINEUP_PLEX_REFRESH_SERVERS_CHANNEL =
  'lineup:plex:refreshServers' as const;

export const LINEUP_PLEX_SELECT_SERVER_CHANNEL =
  'lineup:plex:selectServer' as const;

export const LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL =
  'lineup:plex:listLibrarySections' as const;

export const LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL =
  'lineup:plex:listLibraryItems' as const;

export const LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL =
  'lineup:plex:searchLibrary' as const;

export const LINEUP_PLEX_GET_METADATA_CHANNEL =
  'lineup:plex:getMetadata' as const;

export const LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL =
  'lineup:channelSetup:getStatus' as const;

export const LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL =
  'lineup:channelSetup:startReview' as const;

export const LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL =
  'lineup:channelSetup:startApply' as const;

export const LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL =
  'lineup:channelSetup:getOperation' as const;

export const LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL =
  'lineup:channelSetup:cancel' as const;

export const LINEUP_GUIDE_GET_PRESENTATION_CHANNEL =
  'lineup:guide:getPresentation' as const;

export const LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL =
  'lineup:guide:setLibraryFilter' as const;

export const LINEUP_PLAYER_TUNE_CHANNEL = 'lineup:player:tuneChannel' as const;

export const LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL =
  'lineup:customChannels:getSnapshot' as const;

export const LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL =
  'lineup:customChannels:listMedia' as const;

export const LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL =
  'lineup:customChannels:getMediaMetadata' as const;

export const LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL =
  'lineup:customChannels:validateDraft' as const;

export const LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL =
  'lineup:customChannels:saveDraft' as const;

export const LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL =
  'lineup:customChannels:deleteChannel' as const;

export const LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL =
  'lineup:customChannels:duplicateChannelDraft' as const;

export const LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL =
  'lineup:customChannels:reorderChannels' as const;

export const LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL =
  'lineup:customChannels:setChannelVisibility' as const;

export const LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL =
  'lineup:settings:getSnapshot' as const;

export const LINEUP_SETTINGS_REPLACE_CHANNEL =
  'lineup:settings:replace' as const;
export const LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL =
  'lineup:settings:getAudioOutputs' as const;

/**
 * Known privileged renderer payload field names are denied at contract seams.
 * Review additions/removals with secret-flow and native-handle exposure impact.
 */
export const RENDERER_FORBIDDEN_PAYLOAD_KEYS = [
  'rawMediaUrl',
  'tokenizedUrl',
  'authHeaders',
  'rawAuthHeaders',
  'persistentToken',
  'credentialMaterial',
  'nativeHandle',
  'libmpvObject',
  'engineId',
  'electronApi',
  'nodeApi',
  'rawPlexPayload',
  'streamKey',
  'partKey',
  'secretDiagnostics',
] as const;

export type RendererForbiddenPayloadKey =
  (typeof RENDERER_FORBIDDEN_PAYLOAD_KEYS)[number];
