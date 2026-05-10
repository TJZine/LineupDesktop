import type { DesktopPersistenceStore } from '../../persistence/desktopPersistenceStore.js';
import type { PlexAccountProfileSummary } from '../../../contracts/persistence.js';
import type {
  DesktopPlexCredentialReadResult,
  DesktopPlexCredentialSaveResult,
  PlexAuthProfileSummary,
} from './types.js';
import { toPersistenceProfileSummary } from './types.js';

export interface DesktopPlexCredentialStoreOptions {
  persistenceStore: Pick<
    DesktopPersistenceStore,
    'getRendererSafeSnapshot' | 'savePlexCredential' | 'readPlexCredentialSecret'
  >;
}

export interface SaveDesktopPlexAccountCredentialInput {
  accountId: string;
  secretValue: string;
  profile?: PlexAuthProfileSummary;
}

export class DesktopPlexCredentialStore {
  private readonly persistenceStore: DesktopPlexCredentialStoreOptions['persistenceStore'];

  constructor(options: DesktopPlexCredentialStoreOptions) {
    this.persistenceStore = options.persistenceStore;
  }

  async saveAccountCredential(
    input: SaveDesktopPlexAccountCredentialInput,
  ): Promise<DesktopPlexCredentialSaveResult> {
    const profile = normalizeProfileAccountId(input.accountId, input.profile);
    const saveResult = await this.persistenceStore.savePlexCredential({
      accountId: input.accountId,
      secretValue: input.secretValue,
      profile: toPersistenceProfileSummary(profile),
    });

    if (!saveResult.ok) {
      return {
        ok: false,
        status: saveResult.status,
        profile,
        diagnostics: saveResult.diagnostics,
      };
    }

    return {
      ok: true,
      profile,
      credentialHandle: saveResult.handle,
      diagnostics: saveResult.diagnostics,
    };
  }

  async readAccountCredential(accountId: string): Promise<DesktopPlexCredentialReadResult> {
    const readResult = await this.persistenceStore.readPlexCredentialSecret(accountId);

    if (readResult.status !== 'present') {
      return {
        status: readResult.status,
        accountId,
        diagnostics: readResult.diagnostics,
      };
    }

    const profile = toAuthProfileSummary(accountId, readResult.profile);
    const snapshot = await this.persistenceStore.getRendererSafeSnapshot();
    const credentialHandle = snapshot.credentialHandles.find(
      (handle) => handle.credentialId === readResult.credentialId,
    ) ?? {
      credentialId: readResult.credentialId,
      accountId: readResult.accountId,
      kind: 'plex-account' as const,
      createdAtMs: 0,
      updatedAtMs: 0,
    };

    return {
      status: 'present',
      accountId: readResult.accountId,
      credentialId: readResult.credentialId,
      profile,
      credentialHandle,
      shouldReencrypt: readResult.shouldReencrypt,
      diagnostics: [...readResult.diagnostics, ...snapshot.diagnostics],
    };
  }
}

function toAuthProfileSummary(
  accountId: string,
  profile?: PlexAccountProfileSummary,
): PlexAuthProfileSummary {
  return {
    accountId,
    ...(profile?.username !== undefined ? { username: profile.username } : {}),
    ...(profile?.displayName !== undefined ? { displayName: profile.displayName } : {}),
  };
}

function normalizeProfileAccountId(
  accountId: string,
  profile?: PlexAuthProfileSummary,
): PlexAuthProfileSummary {
  return {
    ...profile,
    accountId,
  };
}
