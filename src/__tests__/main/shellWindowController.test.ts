import test from 'node:test';
import assert from 'node:assert/strict';

import type { BrowserWindow, BrowserWindowConstructorOptions, Rectangle } from 'electron';

import {
  createShellWindowController,
  type ShellWindowScreenDisplay,
} from '../../main/window/shellWindowController.js';

test('shell window controller creates the existing secure shell window shape', () => {
  const createdOptions: BrowserWindowConstructorOptions[] = [];
  const statuses: string[] = [];
  const fakeWindow = new FakeBrowserWindow();

  const controller = createShellWindowController({
    createBrowserWindow: (options) => {
      createdOptions.push(options);
      return fakeWindow.asBrowserWindow();
    },
    screen: createFakeScreen(),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: false,
    publishShellStatus: (status) => statuses.push(status),
  });

  assert.equal(controller.createWindow(), fakeWindow.asBrowserWindow());
  assert.deepEqual(statuses, ['booting']);
  assert.equal(controller.getWindow(), fakeWindow.asBrowserWindow());
  assert.deepEqual(createdOptions, [
    {
      width: 1280,
      height: 720,
      show: true,
      backgroundColor: '#111318',
      webPreferences: {
        preload: '/dist/preload/index.cjs',
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
        webSecurity: true,
        allowRunningInsecureContent: false,
        experimentalFeatures: false,
        webviewTag: false,
      },
    },
  ]);
});

test('shell window controller preserves smoke hidden-window behavior', () => {
  const createdOptions: BrowserWindowConstructorOptions[] = [];
  const controller = createShellWindowController({
    createBrowserWindow: (options) => {
      createdOptions.push(options);
      return new FakeBrowserWindow().asBrowserWindow();
    },
    screen: createFakeScreen(),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: true,
    publishShellStatus: () => undefined,
  });

  controller.createWindow();

  assert.equal(createdOptions[0]?.show, false);
});

test('shell window controller stores normal bounds and restores them after fullscreen', () => {
  const fakeWindow = new FakeBrowserWindow({
    bounds: { x: 1940, y: 30, width: 1100, height: 650 },
  });
  const controller = createShellWindowController({
    createBrowserWindow: () => fakeWindow.asBrowserWindow(),
    screen: createFakeScreen({
      displays: [
        { id: 1, workArea: { x: 0, y: 0, width: 1920, height: 1080 } },
        { id: 7, workArea: { x: 1920, y: 0, width: 2560, height: 1440 } },
      ],
      matchingDisplayId: 7,
    }),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: false,
    publishShellStatus: () => undefined,
  });

  controller.createWindow();
  assert.deepEqual(controller.setFullscreen(true), { enabled: true });
  fakeWindow.emit('enter-full-screen');
  fakeWindow.bounds = { x: 0, y: 0, width: 2560, height: 1440 };
  assert.deepEqual(controller.setFullscreen(false), { enabled: false });
  fakeWindow.emit('leave-full-screen');

  assert.deepEqual(fakeWindow.fullscreenCalls, [true, false]);
  assert.deepEqual(fakeWindow.setBoundsCalls, [{ x: 1940, y: 30, width: 1100, height: 650 }]);
});

test('shell window controller does not replace stored bounds on repeated fullscreen intent', () => {
  const fakeWindow = new FakeBrowserWindow({
    bounds: { x: 40, y: 50, width: 900, height: 600 },
  });
  const controller = createShellWindowController({
    createBrowserWindow: () => fakeWindow.asBrowserWindow(),
    screen: createFakeScreen(),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: false,
    publishShellStatus: () => undefined,
  });

  controller.createWindow();
  controller.setFullscreen(true);
  fakeWindow.bounds = { x: 0, y: 0, width: 1920, height: 1080 };
  controller.setFullscreen(true);
  controller.setFullscreen(false);
  fakeWindow.emit('leave-full-screen');

  assert.deepEqual(fakeWindow.setBoundsCalls, [{ x: 40, y: 50, width: 900, height: 600 }]);
});

test('shell window controller restores bounds after asynchronous fullscreen leave', () => {
  const fakeWindow = new FakeBrowserWindow({
    bounds: { x: 100, y: 120, width: 900, height: 600 },
  });
  const controller = createShellWindowController({
    createBrowserWindow: () => fakeWindow.asBrowserWindow(),
    screen: createFakeScreen(),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: false,
    publishShellStatus: () => undefined,
  });

  controller.createWindow();
  controller.setFullscreen(true);
  fakeWindow.emit('enter-full-screen');
  fakeWindow.bounds = { x: 0, y: 0, width: 1920, height: 1080 };
  controller.setFullscreen(false);

  assert.deepEqual(fakeWindow.setBoundsCalls, []);
  fakeWindow.emit('leave-full-screen');
  assert.deepEqual(fakeWindow.setBoundsCalls, [{ x: 100, y: 120, width: 900, height: 600 }]);
});

test('shell window controller fits stale same-display restore bounds', () => {
  const fakeWindow = new FakeBrowserWindow({
    bounds: { x: 900, y: 40, width: 1400, height: 900 },
  });
  const controller = createShellWindowController({
    createBrowserWindow: () => fakeWindow.asBrowserWindow(),
    screen: createFakeScreen({
      displays: [{ id: 1, workArea: { x: 0, y: 0, width: 1280, height: 720 } }],
      matchingDisplayId: 1,
    }),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: false,
    publishShellStatus: () => undefined,
  });

  controller.createWindow();
  controller.setFullscreen(true);
  fakeWindow.emit('enter-full-screen');
  controller.setFullscreen(false);
  fakeWindow.emit('leave-full-screen');

  assert.deepEqual(fakeWindow.setBoundsCalls, [{ x: 0, y: 0, width: 1280, height: 720 }]);
});

test('shell window controller fits missing-display restore bounds', () => {
  const fakeWindow = new FakeBrowserWindow({
    bounds: { x: 2200, y: 40, width: 1400, height: 900 },
  });
  const controller = createShellWindowController({
    createBrowserWindow: () => fakeWindow.asBrowserWindow(),
    screen: createFakeScreen({
      displays: [{ id: 1, workArea: { x: 0, y: 0, width: 1280, height: 720 } }],
      matchingDisplayId: 9,
    }),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: false,
    publishShellStatus: () => undefined,
  });

  controller.createWindow();
  controller.setFullscreen(true);
  fakeWindow.emit('enter-full-screen');
  controller.setFullscreen(false);
  fakeWindow.emit('leave-full-screen');

  assert.deepEqual(fakeWindow.setBoundsCalls, [{ x: 0, y: 0, width: 1280, height: 720 }]);
});

test('shell window controller returns the existing fullscreen result shape when no window exists', () => {
  const controller = createShellWindowController({
    createBrowserWindow: () => new FakeBrowserWindow().asBrowserWindow(),
    screen: createFakeScreen(),
    preloadPath: '/dist/preload/index.cjs',
    smokeMode: false,
    publishShellStatus: () => undefined,
  });

  assert.deepEqual(controller.setFullscreen(true), { enabled: true });
  assert.deepEqual(controller.setFullscreen(false), { enabled: false });
});

interface FakeBrowserWindowOptions {
  bounds?: Rectangle;
}

class FakeBrowserWindow {
  bounds: Rectangle;
  fullscreen = false;
  destroyed = false;
  readonly fullscreenCalls: boolean[] = [];
  readonly setBoundsCalls: Rectangle[] = [];
  readonly #listeners = new Map<string, Set<() => void>>();

  constructor(options: FakeBrowserWindowOptions = {}) {
    this.bounds = options.bounds ?? { x: 10, y: 20, width: 1280, height: 720 };
  }

  asBrowserWindow(): BrowserWindow {
    return this as unknown as BrowserWindow;
  }

  isDestroyed(): boolean {
    return this.destroyed;
  }

  isFullScreen(): boolean {
    return this.fullscreen;
  }

  getBounds(): Rectangle {
    return { ...this.bounds };
  }

  setFullScreen(enabled: boolean): void {
    this.fullscreenCalls.push(enabled);
    this.fullscreen = enabled;
  }

  setBounds(bounds: Rectangle): void {
    this.setBoundsCalls.push({ ...bounds });
    this.bounds = { ...bounds };
  }

  on(event: string, listener: () => void): this {
    const listeners = this.#listeners.get(event) ?? new Set<() => void>();
    listeners.add(listener);
    this.#listeners.set(event, listeners);
    return this;
  }

  emit(event: string): void {
    if (event === 'enter-full-screen') {
      this.fullscreen = true;
    }
    if (event === 'leave-full-screen') {
      this.fullscreen = false;
    }
    for (const listener of this.#listeners.get(event) ?? []) {
      listener();
    }
  }
}

interface FakeScreenOptions {
  displays?: ShellWindowScreenDisplay[];
  matchingDisplayId?: number;
}

function createFakeScreen(options: FakeScreenOptions = {}) {
  const displays = options.displays ?? [
    { id: 1, workArea: { x: 0, y: 0, width: 1920, height: 1080 } },
  ];
  const matchingDisplayId = options.matchingDisplayId ?? displays[0]?.id ?? 1;
  return {
    getAllDisplays: () => displays,
    getDisplayMatching: () =>
      displays.find((display) => display.id === matchingDisplayId) ?? {
        id: matchingDisplayId,
        workArea: { x: 0, y: 0, width: 1, height: 1 },
      },
    getPrimaryDisplay: () => displays[0] ?? { id: 1, workArea: { x: 0, y: 0, width: 1, height: 1 } },
  };
}
