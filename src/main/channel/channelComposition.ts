import type { App, IpcMainInvokeEvent } from 'electron';

import { redactDiagnosticText } from '../../contracts/diagnostics.js';
import type { ShellMode } from '../../contracts/shell.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import { resolveDesktopAppDataPaths } from '../persistence/appDataPaths.js';
import { DesktopChannelPersistenceStore } from '../persistence/desktopChannelPersistenceStore.js';
import { registerChannelIpcHandlers, type ChannelIpcTeardown } from './channelIpc.js';
import { ChannelRuntime } from './channelRuntime.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';
import { PlexLibraryMinimalAdapter } from './plexLibraryMinimalAdapter.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import { GuideRuntime } from './guideRuntime.js';
import type { ChannelClock, ChannelLogger } from '../../domain/channel/interfaces.js';

export interface RegisterChannelCompositionOptions {
  app: Pick<App, 'getPath'>;
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  plexRuntime: DesktopPlexRuntime;
  onChannelTuned?: (channelId: string) => void | Promise<void>;
  diagnosticEventStore?: DiagnosticEventStore;
}

export type ChannelCompositionTeardown = () => Promise<void>;

export interface ChannelCompositionRegistration {
  guideRuntime: GuideRuntime;
  activeChannelScheduler: ChannelScheduler;
  teardown: ChannelCompositionTeardown;
}

export function registerChannelComposition(
  options: RegisterChannelCompositionOptions,
): ChannelCompositionRegistration {
  const paths = resolveDesktopAppDataPaths(options.app);
  const channelPersistenceFilePath = paths.channelPersistenceFilePath;
  if (channelPersistenceFilePath === undefined) {
    throw new Error('Channel persistence path was not resolved.');
  }
  const clock: ChannelClock = { now: () => Date.now() };
  const runtime = new ChannelRuntime({
    storage: new DesktopChannelPersistenceStore({
      persistenceFilePath: channelPersistenceFilePath,
    }),
    plexRuntime: options.plexRuntime,
    clock,
  });

  const plexLibraryAdapter = new PlexLibraryMinimalAdapter(options.plexRuntime);
  const activeChannelScheduler = new ChannelScheduler({ clock });
  const guideLogger = createGuideRuntimeLogger(options.diagnosticEventStore);
  const guideRuntime = new GuideRuntime({
    repository: runtime.getRepository(),
    plexLibraryAdapter,
    activeChannelScheduler,
    clock,
    onChannelTuned: typeof options.onChannelTuned === 'function' ? options.onChannelTuned : undefined,
    logger: guideLogger,
  });

  const teardownIpc: ChannelIpcTeardown = registerChannelIpcHandlers({
    runtime,
    guideRuntime,
    isAuthorizedEvent: options.isAuthorizedEvent,
    createRequestId: options.createRequestId,
  });

  options.diagnosticEventStore?.record({
    surface: 'main',
    category: 'lifecycle',
    severity: 'info',
    status: 'observed',
    operation: 'channel.composition.register',
    message: 'Channel setup runtime composition registered.',
    context: {
      shellMode: options.shellMode,
      storage: 'main-owned',
    },
  });

  return {
    guideRuntime,
    activeChannelScheduler,
    teardown: async () => {
      await teardownIpc();
    },
  };
}

function createGuideRuntimeLogger(
  diagnosticEventStore: DiagnosticEventStore | undefined,
): ChannelLogger {
  return {
    warn: (message, detail) => {
      diagnosticEventStore?.record({
        surface: 'main',
        category: 'lifecycle',
        severity: 'warning',
        status: 'observed',
        operation: 'channel.guideRuntime.warn',
        message,
        context: sanitizeChannelDiagnosticDetail(detail),
      });
    },
    error: (message, detail) => {
      diagnosticEventStore?.record({
        surface: 'main',
        category: 'lifecycle',
        severity: 'error',
        status: 'failed',
        operation: 'channel.guideRuntime.error',
        message,
        context: sanitizeChannelDiagnosticDetail(detail),
      });
    },
  };
}

export function sanitizeChannelDiagnosticDetail(detail: unknown): Record<string, unknown> {
  if (typeof detail !== 'object' || detail === null || Array.isArray(detail)) {
    return {};
  }
  return sanitizeDiagnosticRecord(detail as Record<string, unknown>, 0);
}

function sanitizeDiagnosticRecord(
  detail: Record<string, unknown>,
  depth: number,
): Record<string, unknown> {
  if (depth > 2) {
    return { summary: 'detail-depth-exceeded' };
  }
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(detail)) {
    if (isSensitiveDiagnosticKey(key)) {
      result[key] = '[redacted]';
      continue;
    }
    if (typeof value === 'string') {
      result[key] = redactDiagnosticText(value).slice(0, 2000);
    } else if (typeof value === 'number' || typeof value === 'boolean' || value === null) {
      result[key] = value;
    } else if (Array.isArray(value)) {
      result[key] = value.slice(0, 20).map((entry) => {
        if (typeof entry === 'string') {
          return redactDiagnosticText(entry).slice(0, 2000);
        }
        if (typeof entry === 'object' && entry !== null) {
          return sanitizeDiagnosticRecord(entry as Record<string, unknown>, depth + 1);
        }
        return entry;
      });
    } else if (typeof value === 'object' && value !== null) {
      result[key] = sanitizeDiagnosticRecord(value as Record<string, unknown>, depth + 1);
    }
  }
  return result;
}

function isSensitiveDiagnosticKey(key: string): boolean {
  return /token|secret|credential|password|auth|header|url|uri|path|file/i.test(key);
}
