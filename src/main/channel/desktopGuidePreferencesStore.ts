import fs from 'node:fs/promises';
import path from 'node:path';
import { Buffer } from 'node:buffer';

import type { GuideLibraryPersistenceStatus } from '../../contracts/guide.js';

const MAX_BYTES = 1024 * 1024;
const MAX_SCOPES = 128;
// eslint-disable-next-line no-control-regex -- the persisted identifier policy explicitly excludes ASCII controls
const IDENTITY_PATTERN = new RegExp('^[^\\u0000-\\u001f\\u007f]{1,512}$', 'u');
const SCOPE_TOKEN_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;

export type GuideFilterStoreErrorCode =
  | 'GUIDE_FILTER_SCOPE_STALE'
  | 'GUIDE_FILTER_REVISION_CONFLICT'
  | 'GUIDE_FILTER_STORAGE_UNAVAILABLE'
  | 'GUIDE_FILTER_UNSUPPORTED_VERSION'
  | 'GUIDE_FILTER_REVISION_EXHAUSTED';

export class DesktopGuidePreferencesStoreError extends Error {
  public constructor(public readonly code: GuideFilterStoreErrorCode) {
    super('Guide preference operation failed.');
    this.name = 'DesktopGuidePreferencesStoreError';
  }
}

export class DesktopGuidePreferencesCommitCurrentnessError extends Error {
  public constructor() {
    super('Guide preference request is no longer current.');
    this.name = 'DesktopGuidePreferencesCommitCurrentnessError';
  }
}

export interface DesktopGuidePreferencesFileSystem {
  readFile(filePath: string, encoding: 'utf8'): Promise<string>;
  mkdir(directoryPath: string, options: { recursive: true }): Promise<unknown>;
  writeFile(filePath: string, content: string, options: { encoding: 'utf8'; mode: number }): Promise<void>;
  chmod(filePath: string, mode: number): Promise<void>;
  rename(sourcePath: string, destinationPath: string): Promise<void>;
  unlink(filePath: string): Promise<void>;
}

export interface GuidePreferenceScope {
  serverId: string;
  profileId: string;
  scopeToken: string;
}

export interface GuidePreferenceSnapshot {
  scopeToken: string;
  revision: number;
  selectedLibraryId: string | null;
  persistenceStatus: GuideLibraryPersistenceStatus;
}

interface GuidePreferenceScopeV1 {
  serverId: string;
  profileId: string;
  selectedLibraryId: string | null;
  revision: number;
}

interface GuidePreferencesV1 {
  schemaVersion: 1;
  scopes: GuidePreferenceScopeV1[];
}

const nodeFileSystem: DesktopGuidePreferencesFileSystem = {
  readFile: (filePath, encoding) => fs.readFile(filePath, encoding),
  mkdir: (directoryPath, options) => fs.mkdir(directoryPath, options),
  writeFile: (filePath, content, options) => fs.writeFile(filePath, content, options),
  chmod: (filePath, mode) => fs.chmod(filePath, mode),
  rename: (sourcePath, destinationPath) => fs.rename(sourcePath, destinationPath),
  unlink: (filePath) => fs.unlink(filePath),
};

export class DesktopGuidePreferencesStore {
  private readonly fileSystem: DesktopGuidePreferencesFileSystem;
  private readonly processId: number;
  private operationChain: Promise<void> = Promise.resolve();
  private tempCounter = 0;
  private scopeEpoch = 0;
  private activeScope: GuidePreferenceScope | null = null;
  private activeSnapshot: GuidePreferenceSnapshot | null = null;
  private document: GuidePreferencesV1 | null = null;

  public constructor(
    private readonly filePath: string,
    options: { fileSystem?: DesktopGuidePreferencesFileSystem; processId?: number } = {},
  ) {
    this.fileSystem = options.fileSystem ?? nodeFileSystem;
    this.processId = options.processId ?? process.pid;
  }

  public activateScope(scope: GuidePreferenceScope): Promise<GuidePreferenceSnapshot> {
    const normalized = normalizeScope(scope);
    if (this.activeScope?.scopeToken === normalized.scopeToken &&
      this.activeScope.serverId === normalized.serverId && this.activeScope.profileId === normalized.profileId &&
      this.activeSnapshot !== null) {
      const epoch = this.scopeEpoch;
      return this.enqueue(async () => {
        if (epoch !== this.scopeEpoch || this.activeSnapshot === null) {
          throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_SCOPE_STALE');
        }
        return this.activeSnapshot;
      });
    }
    this.scopeEpoch += 1;
    const epoch = this.scopeEpoch;
    this.activeScope = normalized;
    this.activeSnapshot = null;
    return this.enqueue(async () => {
      if (epoch !== this.scopeEpoch) throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_SCOPE_STALE');
      const loaded = await this.readDocument();
      if (epoch !== this.scopeEpoch) throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_SCOPE_STALE');
      this.document = loaded.document;
      const record = loaded.document?.scopes.find((candidate) => sameScope(candidate, normalized));
      const snapshot: GuidePreferenceSnapshot = Object.freeze({
        scopeToken: normalized.scopeToken,
        revision: record?.revision ?? 0,
        selectedLibraryId: record?.selectedLibraryId ?? null,
        persistenceStatus: loaded.status,
      });
      this.activeSnapshot = snapshot;
      return snapshot;
    });
  }

  public setLibraryFilter(
    expectedScopeToken: string,
    expectedRevision: number,
    libraryId: string | null,
    isCommitCurrent: () => boolean | Promise<boolean> = () => true,
  ): Promise<GuidePreferenceSnapshot> {
    const selectedLibraryId = libraryId === null ? null : normalizeIdentifier(libraryId);
    const epoch = this.scopeEpoch;
    return this.enqueue(async () => {
      const { scope, snapshot } = this.requireExpected(epoch, expectedScopeToken, expectedRevision);
      if (snapshot.persistenceStatus === 'unsupported-version') {
        throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_UNSUPPORTED_VERSION');
      }
      if (snapshot.revision === Number.MAX_SAFE_INTEGER) {
        throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_REVISION_EXHAUSTED');
      }
      const nextRevision = snapshot.revision + 1;
      const retained = snapshot.persistenceStatus === 'corrupt'
        ? []
        : (this.document?.scopes ?? []).filter((candidate) => !sameScope(candidate, scope));
      const document: GuidePreferencesV1 = {
        schemaVersion: 1,
        scopes: [...retained, {
          serverId: scope.serverId,
          profileId: scope.profileId,
          selectedLibraryId,
          revision: nextRevision,
        }].sort(compareScope),
      };
      if (document.scopes.length > MAX_SCOPES) {
        throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_STORAGE_UNAVAILABLE');
      }
      await this.writeDocument(document, async () => {
        this.requireExpected(epoch, expectedScopeToken, expectedRevision);
        if (!(await isCommitCurrent())) throw new DesktopGuidePreferencesCommitCurrentnessError();
        this.requireExpected(epoch, expectedScopeToken, expectedRevision);
      });
      const next: GuidePreferenceSnapshot = Object.freeze({
        scopeToken: scope.scopeToken,
        revision: nextRevision,
        selectedLibraryId,
        persistenceStatus: 'ready',
      });
      this.document = document;
      this.activeSnapshot = next;
      return next;
    });
  }

  public normalizeSelection(expectedScopeToken: string, expectedRevision: number): Promise<GuidePreferenceSnapshot> {
    return this.setLibraryFilter(expectedScopeToken, expectedRevision, null);
  }

  public clearActiveScope(): void {
    this.scopeEpoch += 1;
    this.activeScope = null;
    this.activeSnapshot = null;
    this.document = null;
  }

  private requireExpected(epoch: number, token: string, revision: number): {
    scope: GuidePreferenceScope;
    snapshot: GuidePreferenceSnapshot;
  } {
    if (epoch !== this.scopeEpoch || this.activeScope === null || this.activeSnapshot === null ||
      this.activeScope.scopeToken !== token) {
      throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_SCOPE_STALE');
    }
    if (this.activeSnapshot.revision !== revision) {
      throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_REVISION_CONFLICT');
    }
    return { scope: this.activeScope, snapshot: this.activeSnapshot };
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.operationChain.then(operation, operation);
    this.operationChain = result.then(() => undefined, () => undefined);
    return result;
  }

  private async readDocument(): Promise<{ status: GuideLibraryPersistenceStatus; document: GuidePreferencesV1 | null }> {
    let content: string;
    try {
      content = await this.fileSystem.readFile(this.filePath, 'utf8');
    } catch (error: unknown) {
      if (isNodeErrorCode(error, 'ENOENT')) return { status: 'missing', document: { schemaVersion: 1, scopes: [] } };
      throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_STORAGE_UNAVAILABLE');
    }
    if (Buffer.byteLength(content, 'utf8') > MAX_BYTES) return { status: 'corrupt', document: null };
    let parsed: unknown;
    try { parsed = JSON.parse(content) as unknown; } catch { return { status: 'corrupt', document: null }; }
    if (isPlainRecord(parsed) && typeof parsed.schemaVersion === 'number' &&
      Number.isSafeInteger(parsed.schemaVersion) && parsed.schemaVersion > 1) {
      return { status: 'unsupported-version', document: null };
    }
    return isGuidePreferencesV1(parsed)
      ? { status: 'ready', document: parsed }
      : { status: 'corrupt', document: null };
  }

  private async writeDocument(document: GuidePreferencesV1, commitBarrier: () => void | Promise<void>): Promise<void> {
    const content = JSON.stringify(document);
    if (Buffer.byteLength(content, 'utf8') > MAX_BYTES) {
      throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_STORAGE_UNAVAILABLE');
    }
    const temporaryPath = `${this.filePath}.${String(this.processId)}.${String(++this.tempCounter)}.tmp`;
    let temporaryCreated = false;
    try {
      await this.fileSystem.mkdir(path.dirname(this.filePath), { recursive: true });
      temporaryCreated = true;
      await this.fileSystem.writeFile(temporaryPath, content, { encoding: 'utf8', mode: 0o600 });
      await this.fileSystem.chmod(temporaryPath, 0o600);
      await commitBarrier();
      await this.fileSystem.rename(temporaryPath, this.filePath);
    } catch (error: unknown) {
      if (temporaryCreated) {
        try { await this.fileSystem.unlink(temporaryPath); } catch { /* best-effort cleanup */ }
      }
      if (error instanceof DesktopGuidePreferencesStoreError ||
        error instanceof DesktopGuidePreferencesCommitCurrentnessError) throw error;
      throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_STORAGE_UNAVAILABLE');
    }
  }
}

function normalizeScope(scope: GuidePreferenceScope): GuidePreferenceScope {
  if (!SCOPE_TOKEN_PATTERN.test(scope.scopeToken)) throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_SCOPE_STALE');
  return Object.freeze({
    serverId: normalizeIdentifier(scope.serverId),
    profileId: normalizeIdentifier(scope.profileId),
    scopeToken: scope.scopeToken,
  });
}

function normalizeIdentifier(value: string): string {
  const normalized = value.trim().normalize('NFC');
  if (value !== normalized || normalized.length > 512 || !IDENTITY_PATTERN.test(normalized)) {
    throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_STORAGE_UNAVAILABLE');
  }
  return normalized;
}

function isGuidePreferencesV1(value: unknown): value is GuidePreferencesV1 {
  if (!isPlainRecord(value) || !hasExactKeys(value, ['schemaVersion', 'scopes']) || value.schemaVersion !== 1 ||
    !Array.isArray(value.scopes) || value.scopes.length > MAX_SCOPES) return false;
  const pairs = new Set<string>();
  for (const scope of value.scopes) {
    if (!isPlainRecord(scope) || !hasExactKeys(scope, ['serverId', 'profileId', 'selectedLibraryId', 'revision']) ||
      !isCanonicalIdentifier(scope.serverId) || !isCanonicalIdentifier(scope.profileId) ||
      !(scope.selectedLibraryId === null || isCanonicalIdentifier(scope.selectedLibraryId)) ||
      typeof scope.revision !== 'number' || !Number.isSafeInteger(scope.revision) || scope.revision < 1) return false;
    const pair = JSON.stringify([scope.serverId, scope.profileId]);
    if (pairs.has(pair)) return false;
    pairs.add(pair);
  }
  return true;
}

function isCanonicalIdentifier(value: unknown): value is string {
  return typeof value === 'string' && value.length <= 512 &&
    value === value.trim().normalize('NFC') && IDENTITY_PATTERN.test(value);
}

function sameScope(left: Pick<GuidePreferenceScopeV1, 'serverId' | 'profileId'>, right: GuidePreferenceScope): boolean {
  return left.serverId === right.serverId && left.profileId === right.profileId;
}

function compareScope(left: GuidePreferenceScopeV1, right: GuidePreferenceScopeV1): number {
  return compareUtf16(left.serverId, right.serverId) || compareUtf16(left.profileId, right.profileId);
}

function compareUtf16(left: string, right: string): number {
  const length = Math.min(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const difference = left.charCodeAt(index) - right.charCodeAt(index);
    if (difference !== 0) return difference;
  }
  return left.length - right.length;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function isNodeErrorCode(error: unknown, code: string): boolean {
  return error instanceof Error && 'code' in error && error.code === code;
}
