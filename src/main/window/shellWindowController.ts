import type { BrowserWindow, BrowserWindowConstructorOptions, Rectangle } from 'electron';

export interface ShellWindowScreenDisplay {
  id: number;
  workArea: Rectangle;
}

export interface ShellWindowScreenPort {
  getAllDisplays(): ShellWindowScreenDisplay[];
  getDisplayMatching(bounds: Rectangle): ShellWindowScreenDisplay;
  getPrimaryDisplay(): ShellWindowScreenDisplay;
}

export interface ShellWindowControllerOptions {
  createBrowserWindow(options: BrowserWindowConstructorOptions): BrowserWindow;
  screen: ShellWindowScreenPort;
  preloadPath: string;
  smokeMode: boolean;
  publishShellStatus(status: 'booting'): void;
}

interface NormalWindowPlacement {
  bounds: Rectangle;
  displayId: number;
}

export interface ShellWindowController {
  createWindow(): BrowserWindow;
  getWindow(): BrowserWindow | null;
  setFullscreen(enabled: boolean): { enabled: boolean };
}

export function createShellWindowController(
  options: ShellWindowControllerOptions,
): ShellWindowController {
  let shellWindow: BrowserWindow | null = null;
  let normalPlacement: NormalWindowPlacement | null = null;
  let stableFullscreen = false;
  let fullscreenIntent: boolean | null = null;

  const getWindow = (): BrowserWindow | null => shellWindow;

  const createWindow = (): BrowserWindow => {
    options.publishShellStatus('booting');
    const createdWindow = options.createBrowserWindow({
      width: 1280,
      height: 720,
      show: !options.smokeMode,
      backgroundColor: '#111318',
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
    shellWindow = createdWindow;
    stableFullscreen = createdWindow.isFullScreen();
    createdWindow.on('enter-full-screen', () => {
      stableFullscreen = true;
      fullscreenIntent = null;
    });
    createdWindow.on('leave-full-screen', () => {
      stableFullscreen = false;
      fullscreenIntent = null;
      restoreNormalPlacement(createdWindow);
    });
    rememberNormalPlacement(createdWindow);
    return createdWindow;
  };

  const setFullscreen = (enabled: boolean): { enabled: boolean } => {
    const window = shellWindow;
    if (window === null || window.isDestroyed()) {
      return { enabled };
    }

    if (enabled) {
      if (fullscreenIntent !== true && !stableFullscreen) {
        rememberNormalPlacement(window);
      }
      fullscreenIntent = true;
      window.setFullScreen(true);
      return { enabled: true };
    }

    fullscreenIntent = false;
    window.setFullScreen(false);
    if (!stableFullscreen) {
      fullscreenIntent = null;
    }
    return { enabled: false };
  };

  const rememberNormalPlacement = (window: BrowserWindow): void => {
    if (window.isDestroyed() || window.isFullScreen()) {
      return;
    }

    const bounds = window.getBounds();
    normalPlacement = {
      bounds,
      displayId: options.screen.getDisplayMatching(bounds).id,
    };
  };

  const restoreNormalPlacement = (window: BrowserWindow): void => {
    if (normalPlacement === null || window.isDestroyed()) {
      return;
    }

    const bounds = boundsForAvailableDisplay(normalPlacement, options.screen);
    window.setBounds(bounds);
  };

  return {
    createWindow,
    getWindow,
    setFullscreen,
  };
}

function boundsForAvailableDisplay(
  placement: NormalWindowPlacement,
  screen: ShellWindowScreenPort,
): Rectangle {
  const matchingDisplay = screen
    .getAllDisplays()
    .find((display) => display.id === placement.displayId);
  if (matchingDisplay !== undefined) {
    return fitBoundsInsideWorkArea(placement.bounds, matchingDisplay.workArea);
  }

  const primaryDisplay = screen.getPrimaryDisplay();
  return fitBoundsInsideWorkArea(placement.bounds, primaryDisplay.workArea);
}

function fitBoundsInsideWorkArea(bounds: Rectangle, workArea: Rectangle): Rectangle {
  const width = Math.min(bounds.width, workArea.width);
  const height = Math.min(bounds.height, workArea.height);
  return {
    x: clamp(bounds.x, workArea.x, workArea.x + workArea.width - width),
    y: clamp(bounds.y, workArea.y, workArea.y + workArea.height - height),
    width,
    height,
  };
}

function clamp(value: number, min: number, max: number): number {
  if (max < min) {
    return min;
  }
  return Math.min(Math.max(value, min), max);
}
