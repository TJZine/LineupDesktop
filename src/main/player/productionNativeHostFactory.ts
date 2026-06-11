import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import * as path from 'node:path';
import * as fs from 'node:fs';
import type { NativePlayerHostPort } from './nativePlayerHostPort.js';
import { NativePlayerHostProcess, type NativePlayerHostChildProcess } from './nativePlayerHostProcess.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';

export interface ProductionNativeHostFactoryOptions {
  diagnosticEventStore?: DiagnosticEventStore;
  requestTimeoutMs?: number;
  cleanupGraceMs?: number;
}

function getElectronApp(): { getAppPath(): string } | null {
  try {
    const require = createRequire(import.meta.url);
    const electron = require('electron') as { app?: { getAppPath(): string } };
    return electron.app ?? null;
  } catch {
    return null;
  }
}

export function getProductionHelperPath(): string | null {
  if (process.platform !== 'win32') {
    return null;
  }

  // 1. Packaged location
  const resourcesPath = (process as any).resourcesPath;
  if (resourcesPath) {
    const packagedPath = path.join(resourcesPath, 'Lineup.NativePlayerHost.exe');
    if (fs.existsSync(packagedPath)) {
      return packagedPath;
    }
  }

  // 2. Local dev location
  try {
    const electronApp = getElectronApp();
    if (!electronApp) {
      return null;
    }
    const appPath = electronApp.getAppPath();
    const devPath = path.join(
      appPath,
      'src',
      'native-helper',
      'Lineup.NativePlayerHost',
      'bin',
      'Release',
      'net8.0',
      'Lineup.NativePlayerHost.exe',
    );
    if (fs.existsSync(devPath)) {
      return devPath;
    }

    const devDebugPath = path.join(
      appPath,
      'src',
      'native-helper',
      'Lineup.NativePlayerHost',
      'bin',
      'Debug',
      'net8.0',
      'Lineup.NativePlayerHost.exe',
    );
    if (fs.existsSync(devDebugPath)) {
      return devDebugPath;
    }
  } catch {
    // app.getAppPath() might throw in test environments before app is ready
  }

  return null;
}

export function createProductionNativeHostFactory(
  options: ProductionNativeHostFactoryOptions = {},
): (() => NativePlayerHostPort) | null {
  const helperPath = getProductionHelperPath();
  if (!helperPath) {
    return null;
  }

  return () => {
    return new NativePlayerHostProcess({
      spawnHostProcess: () => {
        const child = spawn(helperPath, [], {
          stdio: 'pipe',
          windowsHide: true,
        });
        return child as unknown as NativePlayerHostChildProcess;
      },
      requestTimeoutMs: options.requestTimeoutMs,
      cleanupGraceMs: options.cleanupGraceMs,
      diagnosticEventStore: options.diagnosticEventStore,
    });
  };
}
