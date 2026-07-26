import path from 'node:path';

import {
  DESKTOP_PERSISTENCE_DIRECTORY,
  resolveDesktopAppDataPaths,
  type ElectronAppPathProvider,
} from './appDataPaths.js';

export type ChannelPersistenceFileProtectionPolicy =
  | 'posix-0600'
  | 'windows-inherited-userdata-acl';

const readyCapabilityBrand: unique symbol = Symbol('ChannelPersistenceReadyCapability');

export type ChannelPersistenceReadyCapability = Readonly<{
  [readyCapabilityBrand]: true;
  canonicalParentPath: string;
  persistenceFilePath: string;
  protectionPolicy: ChannelPersistenceFileProtectionPolicy;
}>;

export interface ChannelPersistenceBootstrapFileSystem {
  realpath(filePath: string): Promise<string>;
  lstat(filePath: string): Promise<{
    isDirectory(): boolean;
    isSymbolicLink(): boolean;
  }>;
  mkdir(directoryPath: string, options: { recursive: true }): Promise<void>;
}

export type ChannelPersistenceBootstrapResult =
  | Readonly<{ status: 'ready'; capability: ChannelPersistenceReadyCapability }>
  | Readonly<{
      status: 'failed';
      error: Readonly<{
        code: 'CHANNEL_STORAGE_UNAVAILABLE';
        message: 'Channel storage is unavailable.';
      }>;
    }>;

export class ChannelPersistenceBootstrapOwner {
  public constructor(
    private readonly options: Readonly<{
      app: ElectronAppPathProvider;
      fileSystem: ChannelPersistenceBootstrapFileSystem;
      platform: string;
    }>,
  ) {}

  public async bootstrap(): Promise<ChannelPersistenceBootstrapResult> {
    try {
      const paths = resolveDesktopAppDataPaths(this.options.app);
      if (paths.channelPersistenceFilePath === undefined) return bootstrapFailure();
      const canonicalUserData = await this.options.fileSystem.realpath(paths.userDataDirectory);
      const expectedParent = path.join(canonicalUserData, DESKTOP_PERSISTENCE_DIRECTORY);
      const configuredParent = path.dirname(paths.channelPersistenceFilePath);
      if (path.resolve(configuredParent) !== path.resolve(paths.persistenceDirectory)) {
        return bootstrapFailure();
      }
      await this.options.fileSystem.mkdir(configuredParent, { recursive: true });
      const stat = await this.options.fileSystem.lstat(configuredParent);
      if (!stat.isDirectory() || stat.isSymbolicLink()) return bootstrapFailure();
      const canonicalParent = await this.options.fileSystem.realpath(configuredParent);
      if (
        canonicalParent !== expectedParent ||
        !isStrictChild(canonicalUserData, canonicalParent)
      ) {
        return bootstrapFailure();
      }
      return {
        status: 'ready',
        capability: Object.freeze({
          [readyCapabilityBrand]: true as const,
          canonicalParentPath: canonicalParent,
          persistenceFilePath: path.join(
            canonicalParent,
            path.basename(paths.channelPersistenceFilePath),
          ),
          protectionPolicy:
            this.options.platform === 'win32'
              ? 'windows-inherited-userdata-acl'
              : 'posix-0600',
        }),
      };
    } catch {
      return bootstrapFailure();
    }
  }
}

export function isChannelPersistenceReadyCapability(
  value: unknown,
): value is ChannelPersistenceReadyCapability {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype &&
    (value as Partial<ChannelPersistenceReadyCapability>)[readyCapabilityBrand] === true
  );
}

function isStrictChild(parentPath: string, childPath: string): boolean {
  const relative = path.relative(parentPath, childPath);
  return relative.length > 0 && !relative.startsWith('..') && !path.isAbsolute(relative);
}

function bootstrapFailure(): ChannelPersistenceBootstrapResult {
  return {
    status: 'failed',
    error: {
      code: 'CHANNEL_STORAGE_UNAVAILABLE',
      message: 'Channel storage is unavailable.',
    },
  };
}
