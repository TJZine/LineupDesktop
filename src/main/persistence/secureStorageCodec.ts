import type { Buffer } from 'node:buffer';

export interface ElectronSafeStorageLike {
  isAsyncEncryptionAvailable(): Promise<boolean>;
  isEncryptionAvailable(): boolean;
  encryptStringAsync(plainText: string): Promise<Buffer>;
  decryptStringAsync(encrypted: Buffer): Promise<{
    result: string;
    shouldReEncrypt: boolean;
  }>;
  getSelectedStorageBackend?(): string;
}

export type SecureStorageAvailability =
  | {
      available: true;
      backend: 'electron-safe-storage';
      selectedStorageBackend?: string;
    }
  | {
      available: false;
      backend: 'electron-safe-storage';
      reason: 'encryption-unavailable' | 'encryption-check-failed';
      selectedStorageBackend?: string;
    };

export interface SecureStringDecryptResult {
  value: string;
  shouldReencrypt: boolean;
}

export interface SecureStringCodec {
  getAvailability(): Promise<SecureStorageAvailability>;
  encryptString(value: string): Promise<Buffer>;
  decryptString(encrypted: Buffer): Promise<SecureStringDecryptResult>;
}

export class SecureStorageUnavailableError extends Error {
  constructor(message = 'Secure storage encryption is not available.') {
    super(message);
    this.name = 'SecureStorageUnavailableError';
  }
}

/**
 * The safeStorage seam fails closed when Electron reports unavailable or
 * failed encryption checks; persistence does not use a plaintext fallback.
 */
export function createElectronSafeStorageCodec(
  safeStorage: ElectronSafeStorageLike,
): SecureStringCodec {
  return {
    async getAvailability() {
      return getSafeStorageAvailability(safeStorage);
    },
    async encryptString(value) {
      const availability = await getSafeStorageAvailability(safeStorage);
      if (!availability.available) {
        throw new SecureStorageUnavailableError();
      }
      return safeStorage.encryptStringAsync(value);
    },
    async decryptString(encrypted) {
      const availability = await getSafeStorageAvailability(safeStorage);
      if (!availability.available) {
        throw new SecureStorageUnavailableError();
      }
      const decrypted = await safeStorage.decryptStringAsync(encrypted);
      return {
        value: decrypted.result,
        shouldReencrypt: decrypted.shouldReEncrypt,
      };
    },
  };
}

async function getSafeStorageAvailability(
  safeStorage: ElectronSafeStorageLike,
): Promise<SecureStorageAvailability> {
  const selectedStorageBackend = safeStorage.getSelectedStorageBackend?.();

  try {
    const asyncAvailable = await safeStorage.isAsyncEncryptionAvailable();
    const syncAvailable = safeStorage.isEncryptionAvailable();
    if (!asyncAvailable || !syncAvailable) {
      return {
        available: false,
        backend: 'electron-safe-storage',
        reason: 'encryption-unavailable',
        selectedStorageBackend,
      };
    }
    return {
      available: true,
      backend: 'electron-safe-storage',
      selectedStorageBackend,
    };
  } catch {
    return {
      available: false,
      backend: 'electron-safe-storage',
      reason: 'encryption-check-failed',
      selectedStorageBackend,
    };
  }
}
