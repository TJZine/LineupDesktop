export {
  DESKTOP_PLEX_AUTH_METADATA,
  buildPlexAuthRequestHeaders,
  createDesktopPlexAuthConfig,
  createPlexIdentityHeaders,
} from './plexAuthIdentity.js';
export {
  PlexAuthError,
  createPlexAuthHttpError,
  redactAuthErrorText,
  type PlexAuthErrorCode,
} from './plexAuthError.js';
export {
  parseHomeUsersPayload,
  parsePinResponse,
  parseSwitchResponsePayload,
  parseUserResponse,
  readPlexResponse,
  type PlexResponsePayload,
  type PlexTextResponseLike,
} from './plexAuthPayloadParsers.js';
export { parseHomeUsersPayloadData } from './plexHomeUsersPayloadParser.js';
export { parseSwitchPayloadData, type PlexSwitchPayloadResult } from './plexSwitchPayloadParser.js';
export {
  DesktopPlexCredentialStore,
  type SaveDesktopPlexAccountCredentialInput,
} from './desktopPlexCredentialStore.js';
export {
  DesktopPlexAuthService,
  type DesktopPlexAuthServiceOptions,
  type DesktopPlexAuthTransport,
  type DesktopPlexAuthTransportAction,
  type DesktopPlexAuthTransportRequest,
  type DesktopPlexAuthTransportResponse,
  type DesktopPlexPinStatusResult,
  type DesktopPlexPinSummary,
  type DesktopPlexSwitchHomeUserResult,
  type DesktopPlexTokenValidationResult,
} from './desktopPlexAuthService.js';
export type {
  DesktopPlexCredentialReadResult,
  DesktopPlexCredentialSecretReadResult,
  DesktopPlexCredentialSaveResult,
  PlexAuthConfig,
  PlexAuthProfileSummary,
  PlexAuthToken,
  PlexCredentialReadStatus,
  PlexHomeUser,
  PlexPinRequest,
} from './types.js';
