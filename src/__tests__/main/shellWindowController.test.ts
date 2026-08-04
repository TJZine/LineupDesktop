import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { setImmediate } from 'node:timers';
import type { BaseWindow, BaseWindowConstructorOptions, Rectangle, WebContentsView, WebContentsViewConstructorOptions } from 'electron';

import { createShellWindowController } from '../../main/window/shellWindowController.js';
import { NativePlayerPresentationOwner } from '../../main/player/nativePlayerPresentationOwner.js';
import type { NativePlayerPresentationUpdate } from '../../main/player/nativePlayerHostPort.js';

test('shell window controller composes one hidden opaque BaseWindow and transparent sandboxed view', async () => {
  const windowOptions: BaseWindowConstructorOptions[] = [];
  const viewOptions: WebContentsViewConstructorOptions[] = [];
  const fakeWindow = new FakeBaseWindow();
  const fakeView = new FakeView();
  const controller = createShellWindowController({
    createBaseWindow: (options) => { windowOptions.push(options); return fakeWindow.value; },
    createWebContentsView: (options) => { viewOptions.push(options); return fakeView.value; },
    screen: fakeScreen(), preloadPath: '/dist/preload/index.cjs', smokeMode: false,
    publishShellStatus: () => undefined,
  });
  const shell = await controller.createWindow();
  assert.equal(shell.baseWindow, fakeWindow.value);
  assert.equal(shell.webContents, fakeView.webContents);
  assert.deepEqual(windowOptions, [{ width: 1280, height: 720, show: false, backgroundColor: '#111318', frame: true, resizable: true }]);
  assert.deepEqual(viewOptions[0]?.webPreferences, {
    preload: '/dist/preload/index.cjs',
    nodeIntegration: false,
    contextIsolation: true,
    sandbox: true,
    webSecurity: true,
    allowRunningInsecureContent: false,
    experimentalFeatures: false,
    webviewTag: false,
  });
  assert.equal(fakeView.background, '#00000000');
  assert.deepEqual(fakeView.bounds, { x: 0, y: 0, width: 1280, height: 720 });
  controller.showWindow();
  assert.equal(fakeWindow.shown, true);
});

test('shell window controller restores normal placement after fullscreen', async () => {
  const fakeWindow = new FakeBaseWindow({ x: 1940, y: 30, width: 1100, height: 650 });
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => new FakeView().value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: false, publishShellStatus: () => undefined,
  });
  await controller.createWindow();
  controller.setFullscreen(true); fakeWindow.emit('enter-full-screen');
  fakeWindow.bounds = { x: 0, y: 0, width: 1920, height: 1080 };
  controller.setFullscreen(false); fakeWindow.emit('leave-full-screen');
  assert.deepEqual(fakeWindow.setBoundsCalls.at(-1), { x: 820, y: 30, width: 1100, height: 650 });
});

test('shell disposal hides native presentation then closes view, removes it, and destroys window once', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  const fakeView = new FakeView(order);
  fakeWindow.order = order;
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => { order.push('hide'); },
  });
  await controller.createWindow();
  await controller.dispose(); await controller.dispose();
  assert.deepEqual(order, ['hide', 'view-close', 'remove-view', 'window-destroy']);
});

test('destroyed view contents still release the captured view and BaseWindow', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  const fakeView = new FakeView(order);
  fakeWindow.order = order;
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => { order.push('hide'); },
  });
  await controller.createWindow();
  fakeView.destroyed = true;
  fakeView.webContents.emit('destroyed');
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.deepEqual(order, ['hide', 'remove-view', 'window-destroy']);
  assert.equal(controller.getWindow(), null);
});

test('controlled navigation hides before advancing exactly one presentation document epoch', async () => {
  const updates: NativePlayerPresentationUpdate[] = [];
  const owner = new NativePlayerPresentationOwner({
    platform: 'win32',
    host: {
      updatePresentation: async (update) => {
        updates.push(update);
        return { ok: true as const, status: update.mode === 'hidden' ? 'hidden' as const : 'applied' as const };
      },
    },
    getSnapshot: () => ({
      requestId: 'media-1', status: 'playing', media: null, capabilityProfileId: null,
      seekSupport: 'unknown', positionMs: 0, durationMs: null, bufferedRanges: [], playing: true,
      volume: 1, muted: false, playbackRate: 1, selectedAudioTrackId: null,
      selectedSubtitleTrackId: null, selectedVideoTrackId: null, tracks: [],
      quality: { mode: 'unknown', sourceDynamicRange: 'unknown', outputDynamicRangeStatus: 'unknown' }, lastError: null,
    }),
    getParentIdentity: () => ({ hwnd: '42', pid: 9 }),
  });
  const fakeView = new FakeView();
  fakeView.emitNavigationOnLoad = true;
  const controller = createShellWindowController({
    createBaseWindow: () => new FakeBaseWindow().value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: () => owner.hide(),
    invalidatePresentationDocument: () => owner.invalidateDocument(),
  });
  const shell = await controller.createWindow();
  await shell.loadURL('lineup://shell/index.html');
  assert.deepEqual(await owner.update(presentationRequest(null, 1)), {
    ok: true, status: 'deferred', documentEpoch: 2, revision: 1,
  });
  assert.equal((await owner.update(presentationRequest(2, 2))).status, 'applied');
  assert.deepEqual(updates.map(({ documentEpoch, revision, mode }) => ({ documentEpoch, revision, mode })), [
    { documentEpoch: 1, revision: 1, mode: 'hidden' },
    { documentEpoch: 2, revision: 2, mode: 'player-full' },
  ]);
  await controller.dispose();
});

test('construction failures release every resource acquired before the failing stage', async (t) => {
  for (const stage of ['view', 'background', 'add', 'bounds'] as const) {
    await t.test(stage, async () => {
      const order: string[] = [];
      const fakeWindow = new FakeBaseWindow();
      fakeWindow.order = order;
      fakeWindow.throwOnAdd = stage === 'add';
      const fakeView = new FakeView(order);
      fakeView.throwOnBackground = stage === 'background';
      fakeView.throwOnBounds = stage === 'bounds';
      const controller = createShellWindowController({
        createBaseWindow: () => fakeWindow.value,
        createWebContentsView: () => {
          if (stage === 'view') throw new Error('view failed');
          return fakeView.value;
        },
        screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
        hidePresentation: async () => { order.push('hide'); },
      });
      await assert.rejects(controller.createWindow(), /failed/u);
      assert.equal(fakeWindow.destroyed, true);
      assert.equal(controller.getWindow(), null);
      assert.equal(order.includes('hide'), true);
      if (stage !== 'view') assert.equal(fakeView.destroyed, true);
    });
  }
});

test('partial construction waits for delayed presentation hide before releasing resources', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  fakeView.throwOnBounds = true;
  const hideSettlers: Array<() => void> = [];
  const hideGate = new Promise<void>((resolve) => { hideSettlers.push(resolve); });
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => {
      order.push('hide-start');
      await hideGate;
      order.push('hide-settled');
    },
  });
  const creation = controller.createWindow();
  await Promise.resolve();
  assert.deepEqual(order, ['hide-start']);
  assert.equal(fakeView.destroyed, false);
  assert.equal(fakeWindow.destroyed, false);
  const settleHide = hideSettlers[0];
  if (settleHide === undefined) throw new Error('Expected delayed hide settlement.');
  settleHide();
  await assert.rejects(creation, /bounds failed/u);
  assert.deepEqual(order, ['hide-start', 'hide-settled', 'view-close', 'remove-view', 'window-destroy']);
});

test('partial construction reports hide rejection and still releases every resource afterward', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  fakeView.throwOnBounds = true;
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => { order.push('hide-rejected'); throw new Error('hide failed'); },
  });
  await assert.rejects(
    controller.createWindow(),
    (error) => error instanceof AggregateError && error.errors.length === 2 &&
      error.errors[0] instanceof Error && error.errors[0].message === 'bounds failed' &&
      error.errors[1] instanceof Error && error.errors[1].message === 'hide failed',
  );
  assert.deepEqual(order, ['hide-rejected', 'view-close', 'remove-view', 'window-destroy']);
  assert.equal(controller.getWindow(), null);
});

test('failed final hide still releases captured shell resources and reports the failure', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => { order.push('hide'); throw new Error('hide failed'); },
  });
  await controller.createWindow();
  await assert.rejects(controller.dispose(), /hide failed/u);
  assert.deepEqual(order, ['hide', 'view-close', 'remove-view', 'window-destroy']);
  assert.equal(controller.getWindow(), null);
});

test('never-settling final hide times out, releases resources once, and remains idempotent', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  let hideCalls = 0;
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: () => { hideCalls += 1; return new Promise<never>(() => undefined); },
    presentationHideTimeoutMs: 1,
  });
  await controller.createWindow();
  const firstDisposal = controller.dispose();
  assert.equal(controller.dispose(), firstDisposal);
  await assert.rejects(firstDisposal, /hide timed out/u);
  assert.equal(hideCalls, 1);
  assert.deepEqual(order, ['view-close', 'remove-view', 'window-destroy']);
  assert.equal(controller.getWindow(), null);
});

test('presentation hide rejection after the disposal timeout remains handled', async () => {
  const fakeWindow = new FakeBaseWindow();
  const fakeView = new FakeView();
  const pendingHide: { reject?: (error: Error) => void } = {};
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: () => new Promise<never>((_resolve, reject) => { pendingHide.reject = reject; }),
    presentationHideTimeoutMs: 1,
  });
  await controller.createWindow();
  await assert.rejects(controller.dispose(), /hide timed out/u);
  const rejectLateHide = pendingHide.reject;
  if (rejectLateHide === undefined) throw new Error('Expected a pending presentation hide.');
  rejectLateHide(new Error('late hide rejection'));
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(fakeWindow.destroyed, true);
  assert.equal(fakeView.destroyed, true);
});

test('window close and renderer crash each run bounded shell disposal without leaking resources', async (t) => {
  for (const trigger of ['close', 'render-process-gone'] as const) {
    await t.test(trigger, async () => {
      const order: string[] = [];
      const fakeWindow = new FakeBaseWindow();
      fakeWindow.order = order;
      const fakeView = new FakeView(order);
      const controller = createShellWindowController({
        createBaseWindow: () => fakeWindow.value,
        createWebContentsView: () => fakeView.value,
        screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
        hidePresentation: async () => { order.push('hide'); },
        invalidatePresentationDocument: () => true,
      });
      await controller.createWindow();
      if (trigger === 'close') {
        let prevented = false;
        fakeWindow.emit('close', { preventDefault: () => { prevented = true; } });
        assert.equal(prevented, true);
      } else {
        fakeView.webContents.emit('render-process-gone');
      }
      await new Promise<void>((resolve) => setImmediate(resolve));
      assert.deepEqual(order, ['hide', 'view-close', 'remove-view', 'window-destroy']);
      assert.equal(controller.getWindow(), null);
    });
  }
});

test('startup load failure remains bounded and caller disposal releases the shell', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  fakeView.loadError = new Error('load failed');
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => { order.push('hide'); },
    invalidatePresentationDocument: () => true,
  });
  const shell = await controller.createWindow();
  await assert.rejects(shell.loadURL('lineup://shell/index.html'), /load failed/u);
  await controller.dispose();
  assert.deepEqual(order, ['hide', 'hide', 'view-close', 'remove-view', 'window-destroy']);
});

test('startup navigation times out a stalled presentation hide before loading renderer content', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  let hideCalls = 0;
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: () => {
      hideCalls += 1;
      return hideCalls === 1 ? new Promise<never>(() => undefined) : Promise.resolve();
    },
    presentationHideTimeoutMs: 1,
    invalidatePresentationDocument: () => true,
  });
  const shell = await controller.createWindow();

  await assert.rejects(shell.loadURL('lineup://shell/index.html'), /hide timed out/u);
  assert.deepEqual(fakeView.loadedUrls, []);

  await controller.dispose();
  assert.equal(hideCalls, 2);
  assert.deepEqual(order, ['view-close', 'remove-view', 'window-destroy']);
});

test('startup navigation rejects a fulfilled presentation hide failure before loading renderer content', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  let hideCalls = 0;
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => {
      hideCalls += 1;
      return hideCalls === 1
        ? { ok: false, error: { message: 'Native presentation is unavailable.' } }
        : undefined;
    },
    invalidatePresentationDocument: () => true,
  });
  const shell = await controller.createWindow();

  await assert.rejects(
    shell.loadURL('lineup://shell/index.html'),
    /Native presentation is unavailable/u,
  );
  assert.deepEqual(fakeView.loadedUrls, []);

  await controller.dispose();
  assert.equal(hideCalls, 2);
  assert.deepEqual(order, ['view-close', 'remove-view', 'window-destroy']);
});

test('an exhausted document epoch during navigation fails closed and disposes the shell', async () => {
  const order: string[] = [];
  const fakeWindow = new FakeBaseWindow();
  fakeWindow.order = order;
  const fakeView = new FakeView(order);
  const controller = createShellWindowController({
    createBaseWindow: () => fakeWindow.value,
    createWebContentsView: () => fakeView.value,
    screen: fakeScreen(), preloadPath: '/preload', smokeMode: true, publishShellStatus: () => undefined,
    hidePresentation: async () => { order.push('hide'); },
    invalidatePresentationDocument: () => false,
  });
  const shell = await controller.createWindow();
  await assert.rejects(shell.loadURL('lineup://shell/index.html'), /epoch is unavailable/u);
  assert.deepEqual(order, ['hide', 'hide', 'view-close', 'remove-view', 'window-destroy']);
});

class FakeBaseWindow extends EventEmitter {
  bounds: Rectangle;
  fullscreen = false;
  destroyed = false;
  shown = false;
  order: string[] = [];
  readonly setBoundsCalls: Rectangle[] = [];
  throwOnAdd = false;
  readonly contentView = {
    addChildView: (_view: WebContentsView) => {
      if (this.throwOnAdd) throw new Error('add failed');
    },
    removeChildView: (_view: WebContentsView) => { this.order.push('remove-view'); },
  };
  constructor(bounds: Rectangle = { x: 10, y: 20, width: 1280, height: 720 }) { super(); this.bounds = bounds; }
  get value(): BaseWindow { return this as unknown as BaseWindow; }
  isDestroyed(): boolean { return this.destroyed; }
  isFullScreen(): boolean { return this.fullscreen; }
  getBounds(): Rectangle { return { ...this.bounds }; }
  getContentBounds(): Rectangle { return { x: 0, y: 0, width: this.bounds.width, height: this.bounds.height }; }
  setFullScreen(value: boolean): void { this.fullscreen = value; }
  setBounds(value: Rectangle): void { this.bounds = { ...value }; this.setBoundsCalls.push({ ...value }); }
  show(): void { this.shown = true; }
  destroy(): void { this.destroyed = true; this.order.push('window-destroy'); }
}

class FakeView {
  background = '';
  bounds: Rectangle | null = null;
  destroyed = false;
  throwOnBackground = false;
  throwOnBounds = false;
  emitNavigationOnLoad = false;
  loadError: Error | null = null;
  readonly loadedUrls: string[] = [];
  readonly webContents = Object.assign(new EventEmitter(), {
    isDestroyed: () => this.destroyed,
    close: () => { this.destroyed = true; this.order.push('view-close'); },
    loadURL: async (url: string) => {
      this.loadedUrls.push(url);
      if (this.emitNavigationOnLoad) this.webContents.emit('did-start-navigation', { isMainFrame: true });
      if (this.loadError !== null) throw this.loadError;
    },
  });
  constructor(private readonly order: string[] = []) {}
  get value(): WebContentsView { return this as unknown as WebContentsView; }
  setBackgroundColor(value: string): void {
    if (this.throwOnBackground) throw new Error('background failed');
    this.background = value;
  }
  setBounds(value: Rectangle): void {
    if (this.throwOnBounds) throw new Error('bounds failed');
    this.bounds = { ...value };
  }
}

function presentationRequest(documentEpoch: number | null, revision: number) {
  return {
    documentEpoch,
    revision,
    requestId: 'media-1',
    mode: 'player-full' as const,
    rect: { x: 0, y: 0, width: 1, height: 1 },
  };
}

function fakeScreen() {
  return {
    getAllDisplays: () => [{ id: 1, workArea: { x: 0, y: 0, width: 1920, height: 1080 } }],
    getDisplayMatching: (_bounds: Rectangle) => ({ id: 1, workArea: { x: 0, y: 0, width: 1920, height: 1080 } }),
    getPrimaryDisplay: () => ({ id: 1, workArea: { x: 0, y: 0, width: 1920, height: 1080 } }),
  };
}
