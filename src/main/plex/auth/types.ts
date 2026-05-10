import type {
  PersistenceRendererSafeDiagnostic,
  PersistenceRecordStatus,
  PlexAccountProfileSummary,
  PlexCredentialHandle,
} from '../../../contracts/persistence.js';

export interface PlexAuthConfig {
  clientIdentifier: string;
  product: string;
  version: string;
  platform: string;
  platformVersion: string;
  device: string;
  deviceName: string;
}

export interface PlexPinRequest {
  id: number;
  code: string;
  expiresAt: Date;
  authToken: string | null;
  clientIdentifier: string;
}

export interface PlexAuthToken {
  token: string;
  userId: string;
  username: string;
  email: string;
  thumb: string;
  expiresAt: Date | null;
  issuedAt: Date;
  preferredSubtitleLanguage?: string | null;
}

export interface PlexHomeUser {
  id: string;
  title: string;
  thumb: string | null;
  admin: boolean;
  protected: boolean;
  restricted?: boolean;
}

export interface PlexAuthProfileSummary {
  accountId: string;
  username?: string;
  displayName?: string;
  activeProfileId?: string;
  preferredSubtitleLanguage?: string;
}

export type PlexCredentialReadStatus = PersistenceRecordStatus;

export type DesktopPlexCredentialSaveResult =
  | {
      ok: true;
      profile: PlexAuthProfileSummary;
      credentialHandle: PlexCredentialHandle;
      diagnostics: readonly PersistenceRendererSafeDiagnostic[];
    }
  | {
      ok: false;
      status: Exclude<PersistenceRecordStatus, 'present' | 'missing'>;
      profile: PlexAuthProfileSummary;
      diagnostics: readonly PersistenceRendererSafeDiagnostic[];
    };

export type DesktopPlexCredentialReadResult =
  | {
      status: 'present';
      accountId: string;
      credentialId: string;
      profile: PlexAuthProfileSummary;
      credentialHandle: PlexCredentialHandle;
      shouldReencrypt: boolean;
      diagnostics: readonly PersistenceRendererSafeDiagnostic[];
    }
  | {
      status: Exclude<PersistenceRecordStatus, 'present'>;
      accountId: string;
      diagnostics: readonly PersistenceRendererSafeDiagnostic[];
    };

export function toPersistenceProfileSummary(
  profile: PlexAuthProfileSummary,
): PlexAccountProfileSummary {
  return {
    accountId: profile.accountId,
    ...(profile.username !== undefined ? { username: profile.username } : {}),
    ...(profile.displayName !== undefined ? { displayName: profile.displayName } : {}),
  };
}

export function toPlexAuthProfileSummary(token: PlexAuthToken): PlexAuthProfileSummary {
  return {
    accountId: token.userId,
    username: token.username,
    displayName: token.username,
    activeProfileId: token.userId,
    ...(token.preferredSubtitleLanguage
      ? { preferredSubtitleLanguage: token.preferredSubtitleLanguage }
      : {}),
  };
}
