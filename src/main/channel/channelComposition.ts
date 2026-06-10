import type { App, IpcMainInvokeEvent } from 'electron';

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
  const runtime = new ChannelRuntime({
    storage: new DesktopChannelPersistenceStore({
      persistenceFilePath: channelPersistenceFilePath,
    }),
    plexRuntime: options.plexRuntime,
  });

  const plexLibraryAdapter = new PlexLibraryMinimalAdapter(options.plexRuntime);
  const activeChannelScheduler = new ChannelScheduler();
  const guideRuntime = new GuideRuntime({
    repository: runtime.getRepository(),
    plexLibraryAdapter,
    activeChannelScheduler,
    onChannelTuned: options.onChannelTuned,
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
