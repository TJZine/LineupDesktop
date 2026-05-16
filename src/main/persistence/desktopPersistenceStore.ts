import { Buffer } from 'node:buffer';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

import type { PersistenceRecordStatus, PersistenceRendererSafeDiagnostic, PersistenceRendererSafeSnapshot, PlexAccountProfileSummary, PlexCredentialHandle, PlexSelectedServerSummary } from '../../contracts/persistence.js';
import type { SecureStringCodec } from './secureStorageCodec.js';
import { SecureStorageUnavailableError } from './secureStorageCodec.js';

const PERSISTENCE_SCHEMA_VERSION = 1;

export interface DesktopPersistenceStoreOptions { persistenceFilePath: string; secureStringCodec: SecureStringCodec; nowMs?: () => number; }
export interface SavePlexCredentialInput { accountId: string; secretValue: string; profile?: PlexAccountProfileSummary; }
export interface DesktopPersistenceMutationOptions { signal?: AbortSignal | null; }

export type SavePlexCredentialResult =
  | { ok: true; handle: PlexCredentialHandle; diagnostics: readonly PersistenceRendererSafeDiagnostic[] }
  | { ok: false; status: Exclude<PersistenceRecordStatus, 'present' | 'missing'>; diagnostics: readonly PersistenceRendererSafeDiagnostic[] };

export type ReadPlexCredentialSecretResult =
  | {
      status: 'present';
      accountId: string;
      credentialId: string;
      secretValue: string;
      shouldReencrypt: boolean;
      profile?: PlexAccountProfileSummary;
      diagnostics: readonly PersistenceRendererSafeDiagnostic[];
    }
  | {
      status: Exclude<PersistenceRecordStatus, 'present'>;
      diagnostics: readonly PersistenceRendererSafeDiagnostic[];
    };

interface StoredPlexCredential {
  schemaVersion: typeof PERSISTENCE_SCHEMA_VERSION;
  credentialId: string;
  accountId: string;
  kind: 'plex-account';
  encryptedSecretBase64: string;
  createdAtMs: number;
  updatedAtMs: number;
  profile?: PlexAccountProfileSummary;
}

interface PersistenceFile {
  schemaVersion: typeof PERSISTENCE_SCHEMA_VERSION;
  credentials: StoredPlexCredential[];
  selectedServer: PlexSelectedServerSummary | null;
  selectedServersByProfileId?: Record<string, PlexSelectedServerSummary>;
}

type PersistenceFileReadResult =
  | { status: 'present' | 'missing'; value: PersistenceFile; diagnostics: readonly PersistenceRendererSafeDiagnostic[] }
  | { status: 'corrupt'; diagnostics: readonly PersistenceRendererSafeDiagnostic[] };

/** Main-owned credential persistence serializes mutations, schema-checks loads, writes by temp-file rename, and keeps plaintext secrets on main-owned read paths. */
export class DesktopPersistenceStore {
  private readonly persistenceFilePath: string;
  private readonly secureStringCodec: SecureStringCodec;
  private readonly nowMs: () => number;
  private mutationChain: Promise<void> = Promise.resolve();
  private temporaryWriteCounter = 0;

  constructor(options: DesktopPersistenceStoreOptions) {
    this.persistenceFilePath = options.persistenceFilePath;
    this.secureStringCodec = options.secureStringCodec;
    this.nowMs = options.nowMs ?? Date.now;
  }

  async savePlexCredential(
    input: SavePlexCredentialInput,
    options: DesktopPersistenceMutationOptions = {},
  ): Promise<SavePlexCredentialResult> {
    return this.enqueueMutation(async () => {
      throwIfAborted(options.signal);
      const readResult = await this.readPersistenceFile();
      if (readResult.status === 'corrupt') return { ok: false, status: 'corrupt', diagnostics: readResult.diagnostics };

      try {
        throwIfAborted(options.signal);
        const encrypted = await this.secureStringCodec.encryptString(input.secretValue);
        throwIfAborted(options.signal);
        const nowMs = this.nowMs();
        const credentialId = createPlexCredentialId(input.accountId);
        const existing = readResult.value.credentials.find(
          (credential) => credential.credentialId === credentialId,
        );
        const record: StoredPlexCredential = {
          schemaVersion: PERSISTENCE_SCHEMA_VERSION,
          credentialId,
          accountId: input.accountId,
          kind: 'plex-account',
          encryptedSecretBase64: encrypted.toString('base64'),
          createdAtMs: existing?.createdAtMs ?? nowMs,
          updatedAtMs: nowMs,
          profile: input.profile,
        };
        const credentials = [
          ...readResult.value.credentials.filter(
            (credential) => credential.credentialId !== credentialId,
          ),
          record,
        ].sort((left, right) => left.credentialId.localeCompare(right.credentialId));

        await this.writePersistenceFile({ ...readResult.value, credentials }, options);

        return {
          ok: true,
          handle: toCredentialHandle(record),
          diagnostics: [
            {
              component: 'desktop-persistence-store',
              operation: 'save-plex-credential',
              status: 'present',
              credentialId,
              accountId: input.accountId,
              timestampMs: nowMs,
            },
          ],
        };
      } catch (error) {
        if (isAbortError(error)) {
          throw error;
        }
        const unavailable = error instanceof SecureStorageUnavailableError;
        return {
          ok: false,
          status: unavailable ? 'unavailable' : 'corrupt',
          diagnostics: [
            {
              component: 'desktop-persistence-store',
              operation: 'save-plex-credential',
              status: unavailable ? 'unavailable' : 'corrupt',
              reason: unavailable ? 'secure storage unavailable' : 'secure storage encryption failed',
              accountId: input.accountId,
            },
          ],
        };
      }
    });
  }

  async readPlexCredentialSecret(accountId: string): Promise<ReadPlexCredentialSecretResult> {
    const readResult = await this.readPersistenceFile();
    if (readResult.status === 'corrupt') {
      return { status: 'corrupt', diagnostics: readResult.diagnostics };
    }

    const credentialId = createPlexCredentialId(accountId);
    const record = readResult.value.credentials.find(
      (credential) => credential.credentialId === credentialId,
    );
    if (record === undefined) {
      return {
        status: 'missing',
        diagnostics: [
          {
            component: 'desktop-persistence-store',
            operation: 'read-plex-credential',
            status: 'missing',
            credentialId,
            accountId,
          },
        ],
      };
    }

    try {
      const decrypted = await this.secureStringCodec.decryptString(
        Buffer.from(record.encryptedSecretBase64, 'base64'),
      );
      if (decrypted.shouldReencrypt) {
        await this.reencryptCredential(
          record.credentialId,
          record.encryptedSecretBase64,
          decrypted.value,
        );
      }
      return {
        status: 'present',
        accountId,
        credentialId,
        secretValue: decrypted.value,
        shouldReencrypt: decrypted.shouldReencrypt,
        profile: record.profile,
        diagnostics: [
          {
            component: 'desktop-persistence-store',
            operation: 'read-plex-credential',
            status: 'present',
            credentialId,
            accountId,
          },
        ],
      };
    } catch (error) {
      const unavailable = error instanceof SecureStorageUnavailableError;
      return {
        status: unavailable ? 'unavailable' : 'corrupt',
        diagnostics: [
          {
            component: 'desktop-persistence-store',
            operation: 'read-plex-credential',
            status: unavailable ? 'unavailable' : 'corrupt',
            reason: unavailable ? 'secure storage unavailable' : 'credential decrypt failed',
            credentialId,
            accountId,
          },
        ],
      };
    }
  }

  async getSelectedPlexServer(profileId?: string | null): Promise<PlexSelectedServerSummary | null> {
    const readResult = await this.readPersistenceFile();
    if (readResult.status === 'corrupt') {
      return null;
    }
    if (profileId === undefined || profileId === null) {
      return readResult.value.selectedServer;
    }
    const normalizedProfileId = normalizeSelectedServerProfileId(profileId);
    if (normalizedProfileId === null) {
      return null;
    }
    return readResult.value.selectedServersByProfileId?.[normalizedProfileId] ?? null;
  }

  async setSelectedPlexServer(
    profileId: string,
    selectedServer: PlexSelectedServerSummary | null,
    options?: DesktopPersistenceMutationOptions,
  ): Promise<PersistenceRendererSafeSnapshot>;
  async setSelectedPlexServer(
    selectedServer: PlexSelectedServerSummary | null,
    options?: DesktopPersistenceMutationOptions,
  ): Promise<PersistenceRendererSafeSnapshot>;
  async setSelectedPlexServer(
    profileIdOrSelectedServer: string | PlexSelectedServerSummary | null,
    selectedServerOrOptions: PlexSelectedServerSummary | null | DesktopPersistenceMutationOptions = {},
    maybeOptions: DesktopPersistenceMutationOptions = {},
  ): Promise<PersistenceRendererSafeSnapshot> {
    const scoped = typeof profileIdOrSelectedServer === 'string';
    const profileId = scoped ? profileIdOrSelectedServer : null;
    const selectedServer = scoped
      ? selectedServerOrOptions as PlexSelectedServerSummary | null
      : profileIdOrSelectedServer;
    const options = scoped
      ? maybeOptions
      : selectedServerOrOptions as DesktopPersistenceMutationOptions;
    return this.enqueueMutation(async () => {
      throwIfAborted(options.signal);
      const readResult = await this.readPersistenceFile();
      if (readResult.status === 'corrupt') return createCorruptSnapshot(readResult.diagnostics);
      if (!scoped) {
        const value = {
          ...readResult.value,
          selectedServer: sanitizeSelectedServerSummary(selectedServer),
        };
        await this.writePersistenceFile(value, options);
        return this.getRendererSafeSnapshot();
      }
      const normalizedProfileId = normalizeSelectedServerProfileId(profileId ?? '');
      if (normalizedProfileId === null) {
        throw createInvalidSelectedServerProfileError();
      }
      const selectedServersByProfileId = {
        ...(readResult.value.selectedServersByProfileId ?? {}),
      };
      if (selectedServer === null) {
        delete selectedServersByProfileId[normalizedProfileId];
      } else {
        const sanitizedSelectedServer = sanitizeSelectedServerSummary(selectedServer);
        if (sanitizedSelectedServer === null) {
          throw new Error('Selected-server summary is invalid.');
        }
        selectedServersByProfileId[normalizedProfileId] = sanitizedSelectedServer;
      }
      const value = {
        ...readResult.value,
        selectedServersByProfileId,
      };
      await this.writePersistenceFile(value, options);
      return this.getRendererSafeSnapshot();
    });
  }

  async getRendererSafeSnapshot(): Promise<PersistenceRendererSafeSnapshot> {
    const [availability, readResult] = await Promise.all([
      this.secureStringCodec.getAvailability(),
      this.readPersistenceFile(),
    ]);

    if (readResult.status === 'corrupt') {
      return createCorruptSnapshot(readResult.diagnostics);
    }

    const credentialHandles = readResult.value.credentials.map(toCredentialHandle);
    const accounts = readResult.value.credentials
      .map((credential) => credential.profile ?? { accountId: credential.accountId })
      .sort((left, right) => left.accountId.localeCompare(right.accountId));

    return {
      storage: {
        credentials: availability.available ? 'available' : 'unavailable',
        appData: 'available',
        reason: availability.available ? undefined : availability.reason,
      },
      accounts,
      credentialHandles,
      selectedServer: readResult.value.selectedServer,
      diagnostics: [
        ...readResult.diagnostics,
        {
          component: 'desktop-persistence-store',
          operation: 'snapshot',
          status: availability.available ? 'available' : 'unavailable',
          reason: availability.available ? undefined : availability.reason,
          counts: { credentials: credentialHandles.length },
        },
      ],
    };
  }

  private async reencryptCredential(
    credentialId: string,
    expectedEncryptedSecretBase64: string,
    secretValue: string,
  ): Promise<void> {
    await this.enqueueMutation(async () => {
      const readResult = await this.readPersistenceFile();
      if (readResult.status === 'corrupt') return;
      const record = readResult.value.credentials.find(
        (credential) => credential.credentialId === credentialId,
      );
      if (record === undefined) return;
      if (record.encryptedSecretBase64 !== expectedEncryptedSecretBase64) return;
      const encrypted = await this.secureStringCodec.encryptString(secretValue);
      const updatedRecord: StoredPlexCredential = {
        ...record,
        encryptedSecretBase64: encrypted.toString('base64'),
        updatedAtMs: this.nowMs(),
      };
      await this.writePersistenceFile({
        ...readResult.value,
        credentials: readResult.value.credentials.map((credential) =>
          credential.credentialId === credentialId ? updatedRecord : credential,
        ),
      });
    });
  }

  private async readPersistenceFile(): Promise<PersistenceFileReadResult> {
    let content: string;
    try {
      content = await fs.readFile(this.persistenceFilePath, 'utf8');
    } catch (error) {
      if (isNodeFileError(error, 'ENOENT')) {
        return {
          status: 'missing',
          value: createEmptyPersistenceFile(),
          diagnostics: [],
        };
      }
      return {
        status: 'corrupt',
        diagnostics: [
          {
            component: 'desktop-persistence-store',
            operation: 'read-persistence-file',
            status: 'corrupt',
            reason: 'persistence file read failed',
          },
        ],
      };
    }

    try {
      return {
        status: 'present',
        value: parsePersistenceFile(content),
        diagnostics: [],
      };
    } catch {
      return {
        status: 'corrupt',
        diagnostics: [
          {
            component: 'desktop-persistence-store',
            operation: 'read-persistence-file',
            status: 'corrupt',
            reason: 'persistence file validation failed',
          },
        ],
      };
    }
  }

  private async writePersistenceFile(
    value: PersistenceFile,
    options: DesktopPersistenceMutationOptions = {},
  ): Promise<void> {
    throwIfAborted(options.signal);
    await fs.mkdir(path.dirname(this.persistenceFilePath), { recursive: true });
    this.temporaryWriteCounter += 1;
    const temporaryPath = `${this.persistenceFilePath}.${String(process.pid)}.${String(this.temporaryWriteCounter)}.tmp`;
    try {
      throwIfAborted(options.signal);
      await fs.writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
        encoding: 'utf8',
        mode: 0o600,
      });
      throwIfAborted(options.signal);
      await fs.rename(temporaryPath, this.persistenceFilePath);
    } catch (error) {
      await fs.rm(temporaryPath, { force: true }).catch(() => undefined);
      throw error;
    }
    await fs.chmod(this.persistenceFilePath, 0o600);
  }

  private enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const run = this.mutationChain.then(operation, operation);
    this.mutationChain = run.then(() => undefined, () => undefined);
    return run;
  }
}

function throwIfAborted(signal?: AbortSignal | null): void {
  if (signal?.aborted) {
    throw createAbortError();
  }
}

function createAbortError(): Error {
  const error = new Error('Persistence mutation was aborted.');
  error.name = 'AbortError';
  return error;
}

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === 'AbortError';
}

function createEmptyPersistenceFile(): PersistenceFile {
  return {
    schemaVersion: PERSISTENCE_SCHEMA_VERSION,
    credentials: [],
    selectedServer: null,
    selectedServersByProfileId: {},
  };
}

function createCorruptSnapshot(
  diagnostics: readonly PersistenceRendererSafeDiagnostic[],
): PersistenceRendererSafeSnapshot {
  return {
    storage: {
      credentials: 'corrupt',
      appData: 'corrupt',
      reason: 'persistence file is corrupt',
    },
    accounts: [],
    credentialHandles: [],
    selectedServer: null,
    diagnostics,
  };
}

function createPlexCredentialId(accountId: string): string {
  return `plex-account:${encodeURIComponent(accountId)}`;
}

function createInvalidSelectedServerProfileError(): Error {
  const error = new Error('Selected-server profile id is required.');
  error.name = 'InvalidSelectedServerProfileError';
  return error;
}

function normalizeSelectedServerProfileId(profileId: string): string | null {
  const normalized = profileId.trim();
  if (
    normalized.length === 0 ||
    normalized === '__proto__' ||
    normalized === 'prototype' ||
    normalized === 'constructor'
  ) {
    return null;
  }
  return normalized;
}

function toCredentialHandle(record: StoredPlexCredential): PlexCredentialHandle {
  return {
    credentialId: record.credentialId,
    accountId: record.accountId,
    kind: record.kind,
    createdAtMs: record.createdAtMs,
    updatedAtMs: record.updatedAtMs,
  };
}

function parsePersistenceFile(content: string): PersistenceFile {
  const parsed: unknown = JSON.parse(content);
  if (!isPersistenceFile(parsed)) {
    throw new Error('Persistence file schema is invalid.');
  }
  const value = parsed as PersistenceFile;
  return {
    schemaVersion: value.schemaVersion,
    credentials: value.credentials,
    selectedServer: sanitizeSelectedServerSummary(value.selectedServer),
    selectedServersByProfileId: sanitizeSelectedServersByProfileId(
      value.selectedServersByProfileId ?? {},
    ),
  };
}

function isPersistenceFile(value: unknown): value is PersistenceFile {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  const candidate = value as Partial<PersistenceFile>;
  return (
    candidate.schemaVersion === PERSISTENCE_SCHEMA_VERSION &&
    Array.isArray(candidate.credentials) &&
    candidate.credentials.every(isStoredPlexCredential) &&
    (candidate.selectedServer === null || isSelectedServerSummary(candidate.selectedServer)) &&
    (candidate.selectedServersByProfileId === undefined ||
      isSelectedServersByProfileId(candidate.selectedServersByProfileId))
  );
}

function isStoredPlexCredential(value: unknown): value is StoredPlexCredential {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  const candidate = value as Partial<StoredPlexCredential>;
  return (
    candidate.schemaVersion === PERSISTENCE_SCHEMA_VERSION &&
    typeof candidate.credentialId === 'string' &&
    typeof candidate.accountId === 'string' &&
    candidate.kind === 'plex-account' &&
    typeof candidate.encryptedSecretBase64 === 'string' &&
    typeof candidate.createdAtMs === 'number' &&
    typeof candidate.updatedAtMs === 'number' &&
    (candidate.profile === undefined || isAccountProfileSummary(candidate.profile))
  );
}

function isAccountProfileSummary(value: unknown): value is PlexAccountProfileSummary {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  const candidate = value as Partial<PlexAccountProfileSummary>;
  return (
    typeof candidate.accountId === 'string' &&
    (candidate.username === undefined || typeof candidate.username === 'string') &&
    (candidate.displayName === undefined || typeof candidate.displayName === 'string')
  );
}

function isSelectedServerSummary(value: unknown): value is PlexSelectedServerSummary {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  const candidate = value as Partial<PlexSelectedServerSummary>;
  return (
    typeof candidate.serverId === 'string' &&
    typeof candidate.name === 'string' &&
    (candidate.source === 'manual' ||
      candidate.source === 'discovery' ||
      candidate.source === 'restored') &&
    typeof candidate.lastSelectedAtMs === 'number'
  );
}

function sanitizeSelectedServerSummary(value: unknown): PlexSelectedServerSummary | null {
  if (!isSelectedServerSummary(value)) {
    return null;
  }
  return {
    serverId: value.serverId,
    name: value.name,
    source: value.source,
    lastSelectedAtMs: value.lastSelectedAtMs,
  };
}

function isSelectedServersByProfileId(
  value: unknown,
): value is Record<string, PlexSelectedServerSummary> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }
  return Object.entries(value).every(
    ([profileId, selectedServer]) =>
      normalizeSelectedServerProfileId(profileId) !== null &&
      isSelectedServerSummary(selectedServer),
  );
}

function sanitizeSelectedServersByProfileId(
  value: Record<string, PlexSelectedServerSummary>,
): Record<string, PlexSelectedServerSummary> {
  const selectedServersByProfileId: Record<string, PlexSelectedServerSummary> = {};
  for (const [profileId, selectedServer] of Object.entries(value)) {
    const normalizedProfileId = normalizeSelectedServerProfileId(profileId);
    const sanitizedSelectedServer = sanitizeSelectedServerSummary(selectedServer);
    if (normalizedProfileId !== null && sanitizedSelectedServer !== null) {
      selectedServersByProfileId[normalizedProfileId] = sanitizedSelectedServer;
    }
  }
  return selectedServersByProfileId;
}

function isNodeFileError(error: unknown, code: string): boolean {
  return (
    error instanceof Error &&
    'code' in error &&
    typeof error.code === 'string' &&
    error.code === code
  );
}
