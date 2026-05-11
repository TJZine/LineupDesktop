export type PersistenceSecretKind = 'plex-account';

export type PersistenceStorageAvailability = 'available' | 'unavailable';

export type PersistenceRecordStatus = 'present' | 'missing' | 'corrupt' | 'unavailable';

export const PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS = [
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
  'appPath',
  'userDataPath',
  'filesystemPath',
  'encryptedSecret',
  'encryptedSecretBase64',
  'secretValue',
  'secretPlaintext',
  'connectionUri',
  'rawConnectionUri',
] as const;

export type PersistenceForbiddenRendererFieldKey =
  (typeof PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS)[number];

export interface PlexAccountProfileSummary {
  accountId: string;
  username?: string;
  displayName?: string;
}

export interface PlexCredentialHandle {
  credentialId: string;
  accountId: string;
  kind: PersistenceSecretKind;
  createdAtMs: number;
  updatedAtMs: number;
}

export interface PlexSelectedServerSummary {
  serverId: string;
  name: string;
  source: 'manual' | 'discovery' | 'restored';
  lastSelectedAtMs: number;
}

export interface PersistenceRendererSafeDiagnostic {
  component: string;
  operation: string;
  status?: PersistenceRecordStatus | PersistenceStorageAvailability;
  reason?: string;
  credentialId?: string;
  accountId?: string;
  serverId?: string;
  counts?: Readonly<Record<string, number>>;
  timestampMs?: number;
}

export interface PersistenceStorageSummary {
  credentials: PersistenceStorageAvailability | PersistenceRecordStatus;
  appData: PersistenceStorageAvailability | PersistenceRecordStatus;
  reason?: string;
}

export interface PersistenceRendererSafeSnapshot {
  storage: PersistenceStorageSummary;
  accounts: readonly PlexAccountProfileSummary[];
  credentialHandles: readonly PlexCredentialHandle[];
  selectedServer: PlexSelectedServerSummary | null;
  diagnostics: readonly PersistenceRendererSafeDiagnostic[];
}

export function containsPersistenceForbiddenRendererField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => containsPersistenceForbiddenRendererField(item));
  }

  if (value === null || typeof value !== 'object') {
    return false;
  }

  for (const [key, child] of Object.entries(value)) {
    if (
      PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS.includes(
        key as PersistenceForbiddenRendererFieldKey,
      )
    ) {
      return true;
    }
    if (containsPersistenceForbiddenRendererField(child)) {
      return true;
    }
  }

  return false;
}
