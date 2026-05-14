import os from 'node:os';
import { randomUUID } from 'node:crypto';

import type { App, IpcMainInvokeEvent } from 'electron';
import { safeStorage } from 'electron';

import type { ShellMode } from '../../contracts/shell.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import { resolveDesktopAppDataPaths } from '../persistence/appDataPaths.js';
import { DesktopPersistenceStore } from '../persistence/desktopPersistenceStore.js';
import { createElectronSafeStorageCodec } from '../persistence/secureStorageCodec.js';
import {
  createDesktopPlexAuthConfig,
  DesktopPlexAuthService,
} from './auth/index.js';
import { DesktopPlexCredentialStore } from './auth/desktopPlexCredentialStore.js';
import { DesktopPlexSelectedServerStore } from './discovery/desktopPlexSelectedServerStore.js';
import { DesktopPlexServerDiscovery } from './discovery/desktopPlexServerDiscovery.js';
import { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import { LivePlexTransport } from './livePlexTransport.js';
import { registerPlexIpcHandlers, type PlexIpcTeardown } from './plexIpc.js';

export interface RegisterPlexCompositionOptions {
  app: Pick<App, 'getPath' | 'getVersion'>;
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  diagnosticEventStore?: DiagnosticEventStore;
}

export type PlexCompositionTeardown = () => Promise<void>;

export function registerPlexComposition(options: RegisterPlexCompositionOptions): PlexCompositionTeardown {
  const paths = resolveDesktopAppDataPaths(options.app);
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: paths.persistenceFilePath,
    secureStringCodec: createElectronSafeStorageCodec(safeStorage),
  });
  const credentialStore = new DesktopPlexCredentialStore({ persistenceStore });
  const selectedServerStore = new DesktopPlexSelectedServerStore({ persistenceStore });
  const liveTransport = new LivePlexTransport();
  const authService = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({
      clientIdentifier: createDesktopClientIdentifier(),
      platformVersion: os.release(),
      deviceName: 'Lineup Desktop',
    }),
    transport: liveTransport,
    credentialStore,
  });
  const serverDiscovery = new DesktopPlexServerDiscovery({
    transport: liveTransport,
    selectedServerStore,
  });
  const runtime = new DesktopPlexRuntime({
    authService,
    credentialStore,
    serverDiscovery,
    libraryTransport: liveTransport,
    diagnosticEventStore: options.diagnosticEventStore,
  });
  const teardownIpc: PlexIpcTeardown = registerPlexIpcHandlers({
    runtime,
    isAuthorizedEvent: options.isAuthorizedEvent,
    createRequestId: options.createRequestId,
  });

  options.diagnosticEventStore?.record({
    surface: 'main',
    category: 'lifecycle',
    severity: 'info',
    status: 'observed',
    operation: 'plex.composition.register',
    message: 'Plex runtime composition registered.',
    context: {
      shellMode: options.shellMode,
      storage: 'main-owned',
    },
  });

  return async () => {
    await teardownIpc();
  };
}

function createDesktopClientIdentifier(): string {
  return `lineup-desktop-${process.platform}-${randomUUID()}`;
}
