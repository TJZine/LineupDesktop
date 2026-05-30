export type DesktopIpcOwner = 'renderer' | 'preload' | 'main' | 'native-helper';

export type RendererIntent =
  | 'player.load'
  | 'player.play'
  | 'player.pause'
  | 'player.stop'
  | 'player.seekAbsolute'
  | 'player.seekRelative'
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
  'player.pause',
  'player.stop',
  'player.seekAbsolute',
  'player.seekRelative',
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

export const LINEUP_PLAYER_COMMAND_CHANNEL = 'lineup:player:command' as const;

export const LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL =
  'lineup:player:getSnapshot' as const;

export const LINEUP_PLAYER_CLEANUP_CHANNEL = 'lineup:player:cleanup' as const;

export const LINEUP_PLAYER_EVENT_CHANNEL = 'lineup:player:event' as const;

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
