import type { App, IpcMainInvokeEvent } from 'electron';

import type { ShellMode } from '../../contracts/shell.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import { resolveDesktopAppDataPaths } from '../persistence/appDataPaths.js';
import { DesktopChannelPersistenceStore } from '../persistence/desktopChannelPersistenceStore.js';
import { registerChannelIpcHandlers, type ChannelIpcTeardown } from './channelIpc.js';
import { ChannelRuntime } from './channelRuntime.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';

export interface RegisterChannelCompositionOptions {
  app: Pick<App, 'getPath'>;
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  plexRuntime?: Pick<DesktopPlexRuntime, 'getSnapshot' | 'listLibraryItems'>;
  diagnosticEventStore?: DiagnosticEventStore;
}

export type ChannelCompositionTeardown = () => Promise<void>;

export function registerChannelComposition(
  options: RegisterChannelCompositionOptions,
): ChannelCompositionTeardown {
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
  const teardownIpc: ChannelIpcTeardown = registerChannelIpcHandlers({
    runtime,
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

  return async () => {
    await teardownIpc();
  };
}
