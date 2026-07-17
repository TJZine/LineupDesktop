import path from 'node:path';

export const DESKTOP_PERSISTENCE_DIRECTORY = 'persistence';
export const DESKTOP_PERSISTENCE_FILE_NAME = 'lineup-desktop-persistence.json';
export const DESKTOP_CHANNEL_PERSISTENCE_FILE_NAME = 'lineup-desktop-channels.json';
export const DESKTOP_CHANNEL_SETUP_RECORD_FILE_NAME = 'lineup-desktop-channel-setup.json';
export const DESKTOP_SETTINGS_FILE_NAME = 'lineup-desktop-settings.json';

export interface ElectronAppPathProvider {
  getPath(name: 'userData'): string;
}

export interface DesktopAppDataPaths {
  userDataDirectory: string;
  persistenceDirectory: string;
  persistenceFilePath: string;
  channelPersistenceFilePath?: string;
  channelSetupRecordFilePath?: string;
}

export function resolveDesktopAppDataPaths(app: ElectronAppPathProvider): DesktopAppDataPaths {
  const userDataDirectory = app.getPath('userData');
  const persistenceDirectory = path.join(userDataDirectory, DESKTOP_PERSISTENCE_DIRECTORY);

  return {
    userDataDirectory,
    persistenceDirectory,
    persistenceFilePath: path.join(persistenceDirectory, DESKTOP_PERSISTENCE_FILE_NAME),
    channelPersistenceFilePath: path.join(
      persistenceDirectory,
      DESKTOP_CHANNEL_PERSISTENCE_FILE_NAME,
    ),
    channelSetupRecordFilePath: path.join(
      persistenceDirectory,
      DESKTOP_CHANNEL_SETUP_RECORD_FILE_NAME,
    ),
  };
}

export function resolveDesktopSettingsFilePath(app: ElectronAppPathProvider): string {
  return path.join(app.getPath('userData'), DESKTOP_SETTINGS_FILE_NAME);
}
