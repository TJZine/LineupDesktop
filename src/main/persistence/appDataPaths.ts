import path from 'node:path';

export const DESKTOP_PERSISTENCE_DIRECTORY = 'persistence';
export const DESKTOP_PERSISTENCE_FILE_NAME = 'lineup-desktop-persistence.json';

export interface ElectronAppPathProvider {
  getPath(name: 'userData'): string;
}

export interface DesktopAppDataPaths {
  userDataDirectory: string;
  persistenceDirectory: string;
  persistenceFilePath: string;
}

export function resolveDesktopAppDataPaths(app: ElectronAppPathProvider): DesktopAppDataPaths {
  const userDataDirectory = app.getPath('userData');
  const persistenceDirectory = path.join(userDataDirectory, DESKTOP_PERSISTENCE_DIRECTORY);

  return {
    userDataDirectory,
    persistenceDirectory,
    persistenceFilePath: path.join(persistenceDirectory, DESKTOP_PERSISTENCE_FILE_NAME),
  };
}
