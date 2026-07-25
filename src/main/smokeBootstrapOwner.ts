import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const LINEUP_SMOKE_SENTINEL_NAME = '.lineup-desktop-smoke-sentinel';

const smokeCapabilityBrand: unique symbol = Symbol('SmokeBootstrapCapability');

export type SmokeBootstrapCapability = Readonly<{
  [smokeCapabilityBrand]: true;
  canonicalRoot: string;
  protectionPolicy: 'posix-0600' | 'windows-inherited-userdata-acl';
}>;

export type SmokeBootstrapResult =
  | Readonly<{ status: 'normal'; capability: null }>
  | Readonly<{ status: 'smoke'; capability: SmokeBootstrapCapability }>
  | Readonly<{
      status: 'failed';
      error: Readonly<{
        code: 'SMOKE_BOOTSTRAP_INVALID';
        message: 'Smoke bootstrap validation failed.';
      }>;
    }>;

export interface SmokeBootstrapApp {
  getPath(name: 'userData' | 'appData'): string;
  getName(): string;
}

export class SmokeBootstrapOwner {
  public constructor(
    private readonly options: Readonly<{
      app: SmokeBootstrapApp;
      argv: readonly string[];
      environment: Readonly<Record<string, string | undefined>>;
      platform: string;
      temporaryDirectory?: string;
    }>,
  ) {}

  public validate(): SmokeBootstrapResult {
    const smokeRootArgument = readArgument(this.options.argv, '--lineup-smoke-root=');
    const userDataArgument = readArgument(this.options.argv, '--user-data-dir=');
    const smokeFlag = this.options.environment.LINEUP_DESKTOP_SMOKE;
    const nonce = this.options.environment.LINEUP_DESKTOP_SMOKE_NONCE;
    const hasAnyMarker =
      smokeFlag !== undefined ||
      nonce !== undefined ||
      smokeRootArgument !== null ||
      userDataArgument !== null;
    if (!hasAnyMarker) return { status: 'normal', capability: null };
    if (
      smokeFlag !== '1' ||
      nonce === undefined ||
      !/^[a-f0-9]{64}$/u.test(nonce) ||
      smokeRootArgument === null ||
      userDataArgument === null
    ) {
      return smokeFailure();
    }

    try {
      const canonicalRoot = fs.realpathSync(smokeRootArgument);
      const canonicalArgumentUserData = fs.realpathSync(userDataArgument);
      const canonicalAppUserData = fs.realpathSync(this.options.app.getPath('userData'));
      const canonicalTemporaryDirectory = fs.realpathSync(
        this.options.temporaryDirectory ?? os.tmpdir(),
      );
      const canonicalAppData = fs.realpathSync(this.options.app.getPath('appData'));
      const normalUserData = path.resolve(canonicalAppData, this.options.app.getName());
      if (
        canonicalRoot !== canonicalArgumentUserData ||
        canonicalRoot !== canonicalAppUserData ||
        canonicalRoot === normalUserData ||
        !isStrictChild(canonicalTemporaryDirectory, canonicalRoot) ||
        !path.basename(canonicalRoot).includes(nonce) ||
        fs.lstatSync(smokeRootArgument).isSymbolicLink() ||
        fs.lstatSync(userDataArgument).isSymbolicLink()
      ) {
        return smokeFailure();
      }

      const sentinelPath = path.join(canonicalRoot, LINEUP_SMOKE_SENTINEL_NAME);
      const sentinelStat = fs.lstatSync(sentinelPath);
      if (
        sentinelStat.isSymbolicLink() ||
        !sentinelStat.isFile() ||
        (this.options.platform !== 'win32' && (sentinelStat.mode & 0o777) !== 0o600)
      ) {
        return smokeFailure();
      }
      const parsed = JSON.parse(fs.readFileSync(sentinelPath, 'utf8')) as unknown;
      if (
        !isExactSentinel(parsed, nonce)
      ) {
        return smokeFailure();
      }
      return {
        status: 'smoke',
        capability: Object.freeze({
          [smokeCapabilityBrand]: true as const,
          canonicalRoot,
          protectionPolicy:
            this.options.platform === 'win32'
              ? 'windows-inherited-userdata-acl'
              : 'posix-0600',
        }),
      };
    } catch {
      return smokeFailure();
    }
  }
}

export function isSmokeBootstrapCapability(value: unknown): value is SmokeBootstrapCapability {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype &&
    (value as Partial<SmokeBootstrapCapability>)[smokeCapabilityBrand] === true
  );
}

function readArgument(argv: readonly string[], prefix: string): string | null {
  const matches = argv.filter((argument) => argument.startsWith(prefix));
  if (matches.length !== 1) return null;
  const value = matches[0]?.slice(prefix.length) ?? '';
  return value.length > 0 ? value : null;
}

function isStrictChild(parentPath: string, childPath: string): boolean {
  const relative = path.relative(parentPath, childPath);
  return relative.length > 0 && !relative.startsWith('..') && !path.isAbsolute(relative);
}

function isExactSentinel(value: unknown, nonce: string): boolean {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false;
  const record = value as Record<string, unknown>;
  return (
    Object.keys(record).length === 2 &&
    record.mode === 'lineup-desktop-smoke-v1' &&
    record.nonce === nonce
  );
}

function smokeFailure(): SmokeBootstrapResult {
  return {
    status: 'failed',
    error: {
      code: 'SMOKE_BOOTSTRAP_INVALID',
      message: 'Smoke bootstrap validation failed.',
    },
  };
}
