import type { AppRouteId } from '../navigation.js';
import type { AudioSetupState } from './audioSetupRuntime.js';

export function canActivateRouteDuringAudioSetup(
  currentRoute: AppRouteId,
  audioSetupStatus: AudioSetupState['status'],
  nextRoute: AppRouteId,
): boolean {
  return currentRoute !== 'audioSetup' ||
    (audioSetupStatus !== 'loading' && audioSetupStatus !== 'saving') ||
    nextRoute === 'audioSetup';
}
