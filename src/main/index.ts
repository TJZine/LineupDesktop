import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  app,
  BrowserWindow,
  ipcMain,
  screen,
  type IpcMainInvokeEvent,
  session,
} from 'electron';

import {
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
} from '../contracts/ipc.js';
import {
  LINEUP_APP_NAME,
  LINEUP_SHELL_URL,
  type ShellCapabilities,
  type ShellMode,
  type ShellStatusEvent,
  type WindowFullscreenState,
  isWindowFullscreenIntentEnvelope,
  shellFailure,
  shellSuccess,
} from '../contracts/shell.js';
import type { PlayerEvent } from '../contracts/player.js';
import { registerLineupProtocolHandler, registerLineupProtocolScheme } from './protocol.js';
import { redactMainProcessError, reportMainProcessDiagnostic } from './redactedDiagnostics.js';
import {
  isAllowedShellUrl,
  isAuthorizedShellIpcRequest,
  type ShellIpcAuthorizationDetails,
} from './shellSecurity.js';
import { registerPlayerIpcHandlers, type PlayerIpcTeardown } from './player/playerIpc.js';
import { DiagnosticEventStore } from './diagnostics/diagnosticEventStore.js';
import { registerDiagnosticsIpcHandlers, type DiagnosticsIpcTeardown } from './diagnostics/supportBundleIpc.js';
import { registerChannelComposition, type ChannelCompositionTeardown } from './channel/channelComposition.js';
import { registerPlexComposition, type PlexCompositionTeardown } from './plex/plexComposition.js';
import { runSmokeAssertions, type ShellContainmentCounters } from './smokeAssertions.js';
import { registerShellAppCommandController } from './window/shellAppCommandController.js';
import { createShellWindowController } from './window/shellWindowController.js';

registerLineupProtocolScheme();

const currentFile = fileURLToPath(import.meta.url);
const appRoot = path.resolve(path.dirname(currentFile), '..');
const rendererRoot = path.join(appRoot, 'renderer');
const preloadPath = path.join(appRoot, 'preload', 'index.cjs');
const shellMode = getShellMode();
const smokeMode = shellMode === 'smoke';
const diagnosticEventStore = new DiagnosticEventStore();

const shellWindowController = createShellWindowController({
  createBrowserWindow: (options) => new BrowserWindow(options),
  screen,
  preloadPath,
  smokeMode,
  publishShellStatus,
});
let teardownPlayerIpc: PlayerIpcTeardown | null = null;
let teardownDiagnosticsIpc: DiagnosticsIpcTeardown | null = null;
let teardownPlexComposition: PlexCompositionTeardown | null = null;
let teardownChannelComposition: ChannelCompositionTeardown | null = null;
let playerIpcQuitTeardownInProgress = false;
let playerIpcQuitTeardownComplete = false;
let containmentCounters: ShellContainmentCounters = {
  navigationDenied: 0,
  windowOpenDenied: 0,
  permissionDenied: 0,
  webviewDenied: 0,
};

app.commandLine.appendSwitch('disable-gpu');

app.whenReady()
  .then(async () => {
    registerLineupProtocolHandler(rendererRoot);
    configurePermissionContainment();
    registerShellIpcHandlers();
    teardownDiagnosticsIpc = registerDiagnosticsIpcHandlers({
      eventStore: diagnosticEventStore,
      shellMode,
      isAuthorizedEvent,
      createRequestId,
      getShellWindow: () => shellWindowController.getWindow(),
      appVersion: app.getVersion(),
    });
    teardownPlayerIpc = registerPlayerIpcHandlers({
      shellMode,
      isAuthorizedEvent,
      sendPlayerEvent,
      createRequestId,
      reportDiagnostic: reportMainProcessDiagnostic,
      diagnosticEventStore,
    });
    teardownPlexComposition = await registerPlexComposition({
      app,
      shellMode,
      isAuthorizedEvent,
      createRequestId,
      diagnosticEventStore,
    });
    teardownChannelComposition = registerChannelComposition({
      app,
      shellMode,
      isAuthorizedEvent,
      createRequestId,
      diagnosticEventStore,
    });
    const shellWindow = shellWindowController.createWindow();
    registerShellAppCommandController(shellWindow, {
      reportDiagnostic: reportMainProcessDiagnostic,
    });
    attachContainmentHandlers(shellWindow);
    await shellWindow.loadURL(LINEUP_SHELL_URL);
    if (!isAllowedShellUrl(shellWindow.webContents.getURL())) {
      throw new Error('Renderer loaded an unexpected URL.');
    }
    publishShellStatus('ready');
    if (smokeMode) {
      await runSmokeAssertions(shellWindow, containmentCounters);
      app.exit(0);
    }
  })
  .catch((error: unknown) => {
    console.error(redactError(error));
    app.exit(1);
  });

app.on('window-all-closed', () => {
  app.quit();
});

app.on('before-quit', (event) => {
  publishShellStatus('closing');
  const teardown = teardownPlayerIpc;
  if (playerIpcQuitTeardownComplete || teardown === null) {
    const teardownPlex = teardownPlexComposition;
    teardownPlexComposition = null;
    const teardownChannel = teardownChannelComposition;
    teardownChannelComposition = null;
    void Promise.all([
      teardownPlex?.() ?? Promise.resolve(),
      teardownChannel?.() ?? Promise.resolve(),
    ]).catch((error: unknown) => {
      reportMainProcessDiagnostic('Runtime composition cleanup failed during quit', error);
    });
    return;
  }
  if (playerIpcQuitTeardownInProgress) {
    event.preventDefault();
    return;
  }

  event.preventDefault();
  teardownPlayerIpc = null;
  teardownDiagnosticsIpc?.();
  teardownDiagnosticsIpc = null;
  const teardownPlex = teardownPlexComposition;
  teardownPlexComposition = null;
  const teardownChannel = teardownChannelComposition;
  teardownChannelComposition = null;
  playerIpcQuitTeardownInProgress = true;
  Promise.all([
    teardown(),
    teardownPlex?.() ?? Promise.resolve(),
    teardownChannel?.() ?? Promise.resolve(),
  ])
    .catch((error: unknown) => {
      reportMainProcessDiagnostic('Player IPC cleanup failed during quit', error);
    })
    .finally(() => {
      playerIpcQuitTeardownComplete = true;
      playerIpcQuitTeardownInProgress = false;
      app.quit();
    });
});

function attachContainmentHandlers(window: BrowserWindow): void {
  window.webContents.setWindowOpenHandler(() => {
    containmentCounters.windowOpenDenied += 1;
    return { action: 'deny' };
  });

  window.webContents.on('will-navigate', (event, targetUrl) => {
    if (!isAllowedShellUrl(targetUrl)) {
      containmentCounters.navigationDenied += 1;
      event.preventDefault();
    }
  });

  window.webContents.on('will-attach-webview', (event) => {
    containmentCounters.webviewDenied += 1;
    event.preventDefault();
  });

  window.webContents.on('did-navigate', (_event, targetUrl) => {
    if (!isAllowedShellUrl(targetUrl)) {
      window.webContents.stop();
    }
  });
}

function configurePermissionContainment(): void {
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => {
    containmentCounters.permissionDenied += 1;
    callback(false);
  });
  session.defaultSession.setPermissionCheckHandler(() => {
    containmentCounters.permissionDenied += 1;
    return false;
  });
}

function registerShellIpcHandlers(): void {
  ipcMain.handle(LINEUP_SHELL_GET_CAPABILITIES_CHANNEL, (event) => {
    const requestId = createRequestId('shell');
    if (!isAuthorizedEvent(event)) {
      return shellFailure<ShellCapabilities>(requestId, 'unauthorized', 'Request is not authorized.');
    }
    return shellSuccess(requestId, getShellCapabilities());
  });

  ipcMain.handle(LINEUP_WINDOW_INTENT_CHANNEL, (event, payload: unknown) => {
    const requestId = getRequestId(payload);
    if (!isAuthorizedEvent(event)) {
      return shellFailure<WindowFullscreenState>(
        requestId,
        'unauthorized',
        'Request is not authorized.',
      );
    }
    if (!isWindowFullscreenIntentEnvelope(payload)) {
      return shellFailure<WindowFullscreenState>(
        requestId,
        'validation-failed',
        'Window intent payload is invalid.',
      );
    }

    const enabled = payload.intent === 'window.enterFullscreen';
    return shellSuccess(payload.requestId, shellWindowController.setFullscreen(enabled));
  });
}

function isAuthorizedEvent(event: IpcMainInvokeEvent): boolean {
  const shellWindow = shellWindowController.getWindow();
  if (shellWindow === null) {
    return false;
  }
  if (event.senderFrame === null) {
    return false;
  }
  const details: ShellIpcAuthorizationDetails = {
    senderMatchesShell: event.sender === shellWindow.webContents,
    senderDestroyed: event.sender.isDestroyed(),
    senderUrl: event.sender.getURL(),
    frameUrl: event.senderFrame.url,
    frameIsMainFrame: event.senderFrame === event.sender.mainFrame,
  };
  return isAuthorizedShellIpcRequest(details);
}

function getShellCapabilities(): ShellCapabilities {
  const platform = process.platform;
  return {
    appName: LINEUP_APP_NAME,
    appVersion: app.getVersion(),
    platform:
      platform === 'darwin' || platform === 'linux' || platform === 'win32'
        ? platform
        : 'unknown',
    shellMode,
    protocolOrigin: 'lineup://shell',
  };
}

function publishShellStatus(status: ShellStatusEvent['status']): void {
  sendToShellWindow(LINEUP_SHELL_STATUS_CHANGED_CHANNEL, {
    status,
    timestampMs: Date.now(),
  } satisfies ShellStatusEvent);
}

function sendPlayerEvent(event: PlayerEvent): void {
  sendToShellWindow(LINEUP_PLAYER_EVENT_CHANNEL, event);
}

function sendToShellWindow(channel: string, payload: unknown): void {
  const window = shellWindowController.getWindow();
  if (window === null || window.isDestroyed()) {
    return;
  }

  const { webContents } = window;
  if (webContents.isDestroyed()) {
    return;
  }

  try {
    webContents.send(channel, payload);
  } catch (error) {
    reportMainProcessDiagnostic('Shell event delivery failed', error);
  }
}

function getShellMode(): ShellMode {
  if (process.env.LINEUP_DESKTOP_SMOKE === '1') {
    return 'smoke';
  }
  if (process.env.NODE_ENV === 'production') {
    return 'production';
  }
  return 'development';
}

function getRequestId(payload: unknown): string {
  if (
    typeof payload === 'object' &&
    payload !== null &&
    'requestId' in payload &&
    typeof payload.requestId === 'string'
  ) {
    return payload.requestId;
  }
  return createRequestId('invalid');
}

function createRequestId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function redactError(error: unknown): string {
  return redactMainProcessError(error, 'Electron shell startup failed.');
}
