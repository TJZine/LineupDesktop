import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  app,
  BrowserWindow,
  ipcMain,
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
import { LINEUP_CSP, registerLineupProtocolHandler, registerLineupProtocolScheme } from './protocol.js';
import {
  isAllowedShellUrl,
  isAuthorizedShellIpcRequest,
  type ShellIpcAuthorizationDetails,
} from './shellSecurity.js';
import { registerPlayerIpcHandlers, type PlayerIpcTeardown } from './player/playerIpc.js';

registerLineupProtocolScheme();

const currentFile = fileURLToPath(import.meta.url);
const appRoot = path.resolve(path.dirname(currentFile), '..');
const rendererRoot = path.join(appRoot, 'renderer');
const preloadPath = path.join(appRoot, 'preload', 'index.cjs');
const shellMode = getShellMode();
const smokeMode = shellMode === 'smoke';

let shellWindow: BrowserWindow | null = null;
let teardownPlayerIpc: PlayerIpcTeardown | null = null;
let containmentCounters = {
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
    teardownPlayerIpc = registerPlayerIpcHandlers({
      shellMode,
      isAuthorizedEvent,
      sendPlayerEvent,
      createRequestId,
    });
    shellWindow = createShellWindow();
    attachContainmentHandlers(shellWindow);
    await shellWindow.loadURL(LINEUP_SHELL_URL);
    if (!isAllowedShellUrl(shellWindow.webContents.getURL())) {
      throw new Error('Renderer loaded an unexpected URL.');
    }
    publishShellStatus('ready');
    if (smokeMode) {
      await runSmokeAssertions(shellWindow);
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

app.on('before-quit', () => {
  publishShellStatus('closing');
  teardownPlayerIpc?.();
  teardownPlayerIpc = null;
});

function createShellWindow(): BrowserWindow {
  publishShellStatus('booting');
  return new BrowserWindow({
    width: 1280,
    height: 720,
    show: !smokeMode,
    backgroundColor: '#111318',
    webPreferences: {
      preload: preloadPath,
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      allowRunningInsecureContent: false,
      experimentalFeatures: false,
      webviewTag: false,
    },
  });
}

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
    shellWindow?.setFullScreen(enabled);
    return shellSuccess(payload.requestId, { enabled });
  });
}

function isAuthorizedEvent(event: IpcMainInvokeEvent): boolean {
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
  shellWindow?.webContents.send(LINEUP_SHELL_STATUS_CHANGED_CHANNEL, {
    status,
    timestampMs: Date.now(),
  } satisfies ShellStatusEvent);
}

function sendPlayerEvent(event: PlayerEvent): void {
  shellWindow?.webContents.send(LINEUP_PLAYER_EVENT_CHANNEL, event);
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
  if (error instanceof Error) {
    return error.message;
  }
  return 'Electron shell startup failed.';
}

async function runSmokeAssertions(window: BrowserWindow): Promise<void> {
  const result = await window.webContents.executeJavaScript(`
    (async () => {
      const failures = [];
      const csp = document.querySelector("meta[http-equiv='Content-Security-Policy']")?.content;
      const expectedCsp = ${JSON.stringify(LINEUP_CSP)};

      if (document.documentElement.dataset.shellBoot !== 'ready') failures.push('renderer boot');
      if (location.href !== ${JSON.stringify(LINEUP_SHELL_URL)}) failures.push('shell url');
      if (!document.querySelector('[data-shell-status]')?.textContent?.includes('ready')) {
        failures.push('status event');
      }
      if (csp !== expectedCsp) failures.push('csp meta');
      try {
        Function('return 1')();
        failures.push('csp unsafe eval');
      } catch {}
      for (const name of ['process', 'require', 'Buffer']) {
        if (typeof window[name] !== 'undefined') failures.push(name);
      }
      for (const name of ['ipcRenderer', 'electron']) {
        if (typeof window[name] !== 'undefined') failures.push(name);
      }
      if (!window.lineupDesktop?.shell?.getCapabilities) failures.push('shell api');
      if (!window.lineupDesktop?.shell?.onStatusChanged) failures.push('status api');
      if (!window.lineupDesktop?.window?.setFullscreen) failures.push('window api');
      if (!window.lineupDesktop?.player?.dispatch) failures.push('player dispatch api');
      if (!window.lineupDesktop?.player?.getSnapshot) failures.push('player snapshot api');
      if (!window.lineupDesktop?.player?.cleanup) failures.push('player cleanup api');
      if (!window.lineupDesktop?.player?.onEvent) failures.push('player event api');
      if ('ipcRenderer' in window.lineupDesktop) failures.push('raw ipc bridge');
      if ('invoke' in window.lineupDesktop) failures.push('raw invoke bridge');

      const capabilities = await window.lineupDesktop.shell.getCapabilities();
      if (!capabilities.ok || capabilities.value.protocolOrigin !== 'lineup://shell') {
        failures.push('capabilities ' + JSON.stringify(capabilities));
      }
      const playerEvents = [];
      const unsubscribe = window.lineupDesktop.player.onEvent((event) => {
        playerEvents.push(event);
        if (event && typeof event === 'object' && ('sender' in event || 'ports' in event)) {
          failures.push('raw player event object');
        }
      });
      const playerResult = await window.lineupDesktop.player.dispatch({
        intent: 'player.load',
        requestId: 'smoke-player-load',
        payload: {
          media: {
            id: 'smoke-media',
            title: 'Smoke Media',
            durationMs: 1000,
            container: 'smoke',
          },
          policy: {
            autoplay: true,
            startPositionMs: 0,
            preferredAudioTrackId: null,
            preferredSubtitleTrackId: null,
          },
          capabilityProfileId: 'smoke-fake-host',
        },
      });
      const invalidPlayerResult = await window.lineupDesktop.player.dispatch({
        intent: 'player.play',
        requestId: 'smoke-player-invalid',
      });
      const playerSnapshot = await window.lineupDesktop.player.getSnapshot();
      const cleanup = await window.lineupDesktop.player.cleanup();
      unsubscribe();
      const beforeUnsubscribeCount = playerEvents.length;
      await window.lineupDesktop.player.dispatch({
        intent: 'player.play',
        requestId: 'smoke-player-after-unsubscribe',
        payload: {},
      });
      if (playerEvents.length !== beforeUnsubscribeCount) {
        failures.push('player unsubscribe');
      }
      if (!playerResult.ok || !playerResult.value.accepted || playerResult.requestId !== 'smoke-player-load') {
        failures.push('player dispatch ' + JSON.stringify(playerResult));
      }
      if (invalidPlayerResult.ok || invalidPlayerResult.requestId !== 'smoke-player-invalid') {
        failures.push('player invalid request id ' + JSON.stringify(invalidPlayerResult));
      }
      if (!playerSnapshot.ok || playerSnapshot.value.media?.id !== 'smoke-media') {
        failures.push('player snapshot ' + JSON.stringify(playerSnapshot));
      }
      if (!cleanup.ok || cleanup.value.status !== 'idle') {
        failures.push('player cleanup ' + JSON.stringify(cleanup));
      }
      if (!playerEvents.some((event) => event.event === 'state.changed')) {
        failures.push('player event delivery');
      }
      const fullscreenOn = await window.lineupDesktop.window.setFullscreen(true);
      const fullscreenOff = await window.lineupDesktop.window.setFullscreen(false);
      if (!fullscreenOn.ok || fullscreenOn.value.enabled !== true) {
        failures.push('fullscreen on ' + JSON.stringify(fullscreenOn));
      }
      if (!fullscreenOff.ok || fullscreenOff.value.enabled !== false) {
        failures.push('fullscreen off ' + JSON.stringify(fullscreenOff));
      }

      window.open('https://example.com');
      navigator.permissions?.query?.({ name: 'geolocation' }).catch(() => undefined);

      return { failures };
    })();
  `) as { failures: string[] };

  await window.webContents.executeJavaScript(`
    location.assign('https://example.com/disallowed-navigation');
    true;
  `);
  await new Promise((resolve) => setTimeout(resolve, 100));

  if (containmentCounters.navigationDenied < 1) {
    result.failures.push('navigation denial containment');
  }
  if (containmentCounters.windowOpenDenied < 1) {
    result.failures.push('new window containment');
  }
  if (containmentCounters.permissionDenied < 1) {
    result.failures.push('permission containment');
  }
  if (window.webContents.getURL() !== LINEUP_SHELL_URL) {
    result.failures.push('navigation containment');
  }

  if (result.failures.length > 0) {
    throw new Error(`Electron smoke failed: ${result.failures.join(', ')}`);
  }
  console.warn('Electron smoke verification passed.');
}
