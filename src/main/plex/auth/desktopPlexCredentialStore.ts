import type { DesktopPersistenceStore } from '../../persistence/desktopPersistenceStore.js';
import type {
  PersistenceRendererSafeDiagnostic,
  PlexAccountProfileSummary,
} from '../../../contracts/persistence.js';
import type {
  DesktopPlexCredentialReadResult,
  DesktopPlexCredentialSecretReadResult,
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

export interface DesktopPlexCredentialSaveOptions {
  signal?: AbortSignal | null;
}

export class DesktopPlexCredentialStore {
  private readonly persistenceStore: DesktopPlexCredentialStoreOptions['persistenceStore'];

  constructor(options: DesktopPlexCredentialStoreOptions) {
    this.persistenceStore = options.persistenceStore;
  }

  async saveAccountCredential(
    input: SaveDesktopPlexAccountCredentialInput,
    options: DesktopPlexCredentialSaveOptions = {},
  ): Promise<DesktopPlexCredentialSaveResult> {
    throwIfAborted(options.signal);
    const profile = normalizeProfileAccountId(input.accountId, input.profile);
    const saveResult = await this.persistenceStore.savePlexCredential({
      accountId: input.accountId,
      secretValue: input.secretValue,
      profile: toPersistenceProfileSummary(profile),
    }, {
      signal: options.signal ?? null,
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
    const snapshotCredentialHandle = snapshot.credentialHandles.find(
      (handle) => handle.credentialId === readResult.credentialId,
    );
    const credentialHandle = snapshotCredentialHandle ?? {
      credentialId: readResult.credentialId,
      accountId: readResult.accountId,
      kind: 'plex-account' as const,
      createdAtMs: 0,
      updatedAtMs: 0,
    };
    const handleDiagnostics: readonly PersistenceRendererSafeDiagnostic[] =
      snapshotCredentialHandle === undefined
        ? [
            {
              component: 'desktop-plex-credential-store',
              operation: 'read-account-credential',
              status: 'present',
              reason:
                'credential handle missing from renderer-safe snapshot; stub handle with zero timestamps used',
              credentialId: readResult.credentialId,
              accountId: readResult.accountId,
            },
          ]
        : [];

    return {
      status: 'present',
      accountId: readResult.accountId,
      credentialId: readResult.credentialId,
      profile,
      credentialHandle,
      shouldReencrypt: readResult.shouldReencrypt,
      diagnostics: [...readResult.diagnostics, ...snapshot.diagnostics, ...handleDiagnostics],
    };
  }

  async readDefaultAccountCredentialSecret(): Promise<DesktopPlexCredentialSecretReadResult> {
    const snapshot = await this.persistenceStore.getRendererSafeSnapshot();
    const account = snapshot.accounts[0];
    if (account === undefined) {
      return {
        status: snapshot.storage.credentials === 'unavailable'
          ? 'unavailable'
          : snapshot.storage.credentials === 'corrupt'
            ? 'corrupt'
            : 'missing',
        accountId: null,
        diagnostics: snapshot.diagnostics,
      };
    }

    const readResult = await this.persistenceStore.readPlexCredentialSecret(account.accountId);
    if (readResult.status !== 'present') {
      return {
        status: readResult.status,
        accountId: account.accountId,
        diagnostics: [...snapshot.diagnostics, ...readResult.diagnostics],
      };
    }

    return {
      status: 'present',
      accountId: readResult.accountId,
      credentialId: readResult.credentialId,
      secretValue: readResult.secretValue,
      shouldReencrypt: readResult.shouldReencrypt,
      profile: toAuthProfileSummary(readResult.accountId, readResult.profile),
      diagnostics: [...snapshot.diagnostics, ...readResult.diagnostics],
    };
  }
}

function throwIfAborted(signal?: AbortSignal | null): void {
  if (signal?.aborted) {
    const error = new Error('Plex credential save was aborted.');
    error.name = 'AbortError';
    throw error;
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
