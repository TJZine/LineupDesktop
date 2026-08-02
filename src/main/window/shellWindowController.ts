import type {
  BaseWindow,
  BaseWindowConstructorOptions,
  Rectangle,
  WebContents,
  WebContentsView,
  WebContentsViewConstructorOptions,
} from 'electron';

export interface ShellWindowScreenDisplay { id: number; workArea: Rectangle; }
export interface ShellWindowScreenPort {
  getAllDisplays(): ShellWindowScreenDisplay[];
  getDisplayMatching(bounds: Rectangle): ShellWindowScreenDisplay;
  getPrimaryDisplay(): ShellWindowScreenDisplay;
  on?(event: 'display-metrics-changed' | 'display-removed', listener: (...args: unknown[]) => void): void;
  off?(event: 'display-metrics-changed' | 'display-removed', listener: (...args: unknown[]) => void): void;
}

export type ShellWindow = BaseWindow & {
  readonly webContents: WebContents;
  loadURL(url: string): Promise<void>;
};

export interface ShellWindowControllerOptions {
  createBaseWindow(options: BaseWindowConstructorOptions): BaseWindow;
  createWebContentsView(options: WebContentsViewConstructorOptions): WebContentsView;
  screen: ShellWindowScreenPort;
  preloadPath: string;
  smokeMode: boolean;
  publishShellStatus(status: 'booting'): void;
  invalidatePresentationDocument?(): boolean | void;
  hidePresentation?(): Promise<unknown>;
}

interface NormalWindowPlacement { bounds: Rectangle; displayId: number; }
interface OwnedShellResources {
  window: BaseWindow | null;
  view: WebContentsView | null;
  contents: WebContents | null;
}

export interface ShellWindowController {
  createWindow(): Promise<ShellWindow>;
  getWindow(): ShellWindow | null;
  getBaseWindow(): BaseWindow | null;
  setFullscreen(enabled: boolean): { enabled: boolean };
  getNativeParentIdentity(): { hwnd: string; pid: number } | null;
  showWindow(): void;
  dispose(): Promise<void>;
}

export function createShellWindowController(options: ShellWindowControllerOptions): ShellWindowController {
  let shellWindow: ShellWindow | null = null;
  let baseWindow: BaseWindow | null = null;
  let shellView: WebContentsView | null = null;
  let shellContents: WebContents | null = null;
  let normalPlacement: NormalWindowPlacement | null = null;
  let stableFullscreen = false;
  let fullscreenIntent: boolean | null = null;
  let disposed = false;
  const removers: Array<() => void> = [];

  const closePresentationForTransition = (): void => {
    void requestPresentationHide().catch(() => undefined);
  };

  const requestPresentationHide = (): Promise<unknown> => {
    try {
      return options.hidePresentation?.() ?? Promise.resolve();
    } catch (error: unknown) {
      return Promise.reject(error instanceof Error ? error : new Error('Native presentation hide failed.'));
    }
  };

  const createWindow = async (): Promise<ShellWindow> => {
    if (disposed || baseWindow !== null) throw new Error('Shell window is unavailable.');
    options.publishShellStatus('booting');
    try {
      const createdBase = options.createBaseWindow({
        width: 1280,
        height: 720,
        show: false,
        backgroundColor: '#111318',
        frame: true,
        resizable: true,
      });
      baseWindow = createdBase;
      const createdView = options.createWebContentsView({
        webPreferences: {
          preload: options.preloadPath,
          nodeIntegration: false,
          contextIsolation: true,
          sandbox: true,
          webSecurity: true,
          allowRunningInsecureContent: false,
          experimentalFeatures: false,
          webviewTag: false,
        },
      });
      shellView = createdView;
      const createdContents = createdView.webContents;
      shellContents = createdContents;
      createdView.setBackgroundColor('#00000000');
      createdBase.contentView.addChildView(createdView);
      const updateViewBounds = (): void => {
        if (createdBase.isDestroyed() || createdContents.isDestroyed()) return;
        const bounds = createdBase.getContentBounds();
        createdView.setBounds({ x: 0, y: 0, width: bounds.width, height: bounds.height });
      };
      updateViewBounds();

      let controlledNavigationPending = false;
      const loadURL = async (url: string): Promise<void> => {
        await requestPresentationHide();
        if (options.invalidatePresentationDocument?.() === false) {
          await dispose().catch(() => undefined);
          throw new Error('Shell presentation epoch is unavailable.');
        }
        controlledNavigationPending = true;
        try {
          await createdContents.loadURL(url);
        } finally {
          controlledNavigationPending = false;
        }
      };
      Object.defineProperties(createdBase, {
        webContents: { configurable: true, value: createdContents },
        loadURL: { configurable: true, value: loadURL },
      });
      const createdWindow = createdBase as ShellWindow;
      shellWindow = createdWindow;
      stableFullscreen = createdBase.isFullScreen();

      bind(createdBase, 'resize', () => { closePresentationForTransition(); updateViewBounds(); });
      bind(createdBase, 'move', closePresentationForTransition);
      bind(createdBase, 'minimize', closePresentationForTransition);
      bind(createdBase, 'restore', closePresentationForTransition);
      bind(createdBase, 'show', closePresentationForTransition);
      bind(createdBase, 'hide', closePresentationForTransition);
      bind(createdBase, 'enter-full-screen', () => { closePresentationForTransition(); stableFullscreen = true; fullscreenIntent = null; updateViewBounds(); });
      bind(createdBase, 'leave-full-screen', () => { closePresentationForTransition(); stableFullscreen = false; fullscreenIntent = null; restoreNormalPlacement(createdBase); updateViewBounds(); });
      const onClose = (event: { preventDefault(): void }): void => {
        if (disposed) return;
        event.preventDefault();
        void dispose().catch(() => undefined);
      };
      createdBase.on('close', onClose);
      removers.push(() => createdBase.off('close', onClose));
      const onDidStartNavigation = (details: { isMainFrame: boolean }): void => {
        if (!details.isMainFrame) return;
        if (controlledNavigationPending) {
          controlledNavigationPending = false;
          return;
        }
        if (options.invalidatePresentationDocument?.() === false) {
          void dispose().catch(() => undefined);
          return;
        }
        closePresentationForTransition();
      };
      createdContents.on('did-start-navigation', onDidStartNavigation);
      removers.push(() => createdContents.off('did-start-navigation', onDidStartNavigation));
      bindWebContents(createdContents, 'did-finish-load', closePresentationForTransition);
      bindWebContents(createdContents, 'render-process-gone', () => {
        options.invalidatePresentationDocument?.();
        void dispose().catch(() => undefined);
      });
      bindWebContents(createdContents, 'destroyed', () => {
        options.invalidatePresentationDocument?.();
        void dispose().catch(() => undefined);
      });
      bindScreen('display-metrics-changed', closePresentationForTransition);
      bindScreen('display-removed', closePresentationForTransition);
      rememberNormalPlacement(createdBase);
      return createdWindow;
    } catch (error: unknown) {
      disposed = true;
      const resources = captureOwnedResources();
      const constructionError = error instanceof Error ? error : new Error('Shell window construction failed.');
      try {
        await requestPresentationHide();
      } catch (hideError: unknown) {
        const normalizedHideError = hideError instanceof Error ? hideError : new Error('Native presentation hide failed.');
        throw new AggregateError(
          [constructionError, normalizedHideError],
          'Shell construction failed and native presentation could not be hidden.',
          { cause: hideError },
        );
      } finally {
        releaseOwnedResources(resources);
      }
      throw constructionError;
    }
  };

  const bind = (window: BaseWindow, event: string, listener: () => void): void => {
    window.on(event as never, listener);
    removers.push(() => window.off(event as never, listener));
  };
  const bindWebContents = (contents: WebContents, event: string, listener: () => void): void => {
    contents.on(event as never, listener);
    removers.push(() => contents.off(event as never, listener));
  };
  const bindScreen = (event: 'display-metrics-changed' | 'display-removed', listener: () => void): void => {
    options.screen.on?.(event, listener);
    removers.push(() => options.screen.off?.(event, listener));
  };

  const setFullscreen = (enabled: boolean): { enabled: boolean } => {
    const window = baseWindow;
    if (window === null || window.isDestroyed()) return { enabled };
    closePresentationForTransition();
    if (enabled) {
      if (fullscreenIntent !== true && !stableFullscreen) rememberNormalPlacement(window);
      fullscreenIntent = true; window.setFullScreen(true); return { enabled: true };
    }
    fullscreenIntent = false; window.setFullScreen(false);
    if (!stableFullscreen) fullscreenIntent = null;
    return { enabled: false };
  };

  const dispose = async (): Promise<void> => {
    if (disposed) return;
    disposed = true;
    const resources = captureOwnedResources();
    try {
      await requestPresentationHide();
    } finally {
      releaseOwnedResources(resources);
    }
  };

  const captureOwnedResources = (): OwnedShellResources => {
    for (const remove of removers.splice(0)) {
      try { remove(); } catch { /* resource release continues */ }
    }
    const resources = { window: baseWindow, view: shellView, contents: shellContents };
    baseWindow = null;
    shellView = null;
    shellContents = null;
    shellWindow = null;
    return resources;
  };

  const releaseOwnedResources = (resources: OwnedShellResources): void => {
    const { window, view, contents } = resources;
    try { if (contents !== null && !contents.isDestroyed()) contents.close(); } catch { /* continue */ }
    try {
      if (view !== null && window !== null && !window.isDestroyed()) window.contentView.removeChildView(view);
    } catch { /* continue */ }
    try { if (window !== null && !window.isDestroyed()) window.destroy(); } catch { /* already released */ }
  };

  const rememberNormalPlacement = (window: BaseWindow): void => {
    if (window.isDestroyed() || window.isFullScreen()) return;
    const bounds = window.getBounds();
    normalPlacement = { bounds, displayId: options.screen.getDisplayMatching(bounds).id };
  };
  const restoreNormalPlacement = (window: BaseWindow): void => {
    if (normalPlacement === null || window.isDestroyed()) return;
    window.setBounds(boundsForAvailableDisplay(normalPlacement, options.screen));
  };

  return {
    createWindow,
    getWindow: () => shellWindow,
    getBaseWindow: () => baseWindow,
    setFullscreen,
    showWindow: () => { if (!options.smokeMode && baseWindow !== null && !baseWindow.isDestroyed()) baseWindow.show(); },
    getNativeParentIdentity: () => {
      const window = baseWindow;
      if (window === null || window.isDestroyed() || process.platform !== 'win32') return null;
      const handle = window.getNativeWindowHandle();
      if (handle.length !== 4 && handle.length !== 8) return null;
      const value = handle.length === 8 ? handle.readBigUInt64LE(0) : BigInt(handle.readUInt32LE(0));
      return value === 0n ? null : { hwnd: value.toString(10), pid: process.pid };
    },
    dispose,
  };
}

function boundsForAvailableDisplay(placement: NormalWindowPlacement, screen: ShellWindowScreenPort): Rectangle {
  const matching = screen.getAllDisplays().find((display) => display.id === placement.displayId);
  return fitBoundsInsideWorkArea(placement.bounds, (matching ?? screen.getPrimaryDisplay()).workArea);
}
function fitBoundsInsideWorkArea(bounds: Rectangle, workArea: Rectangle): Rectangle {
  const width = Math.min(bounds.width, workArea.width), height = Math.min(bounds.height, workArea.height);
  return { x: clamp(bounds.x, workArea.x, workArea.x + workArea.width - width), y: clamp(bounds.y, workArea.y, workArea.y + workArea.height - height), width, height };
}
function clamp(value: number, min: number, max: number): number { return max < min ? min : Math.min(Math.max(value, min), max); }
