import type { DesktopSettingsValues } from '../../contracts/settings.js';

type GuideDensity = DesktopSettingsValues['guideDensity'];

export interface GuideDensitySettlementPolling {
  hasPendingGuideDensityChange(): boolean;
  noteGuideDensityChange(): void;
  settleGuideDensity(loading: boolean): Promise<void>;
}

export interface SettingsGuideDensitySettlementOwnerOptions {
  getCurrentDensity(): GuideDensity;
  getPolling(): GuideDensitySettlementPolling | undefined;
  retainGuideProgramFocusIntent(): void;
  restorePendingGuideFocus(): void;
}

export interface PendingSettingsGuideDensitySettlement {
  readonly densityChanged: boolean;
  finish(loading: boolean): Promise<void>;
}

export interface SettingsGuideDensitySettlementOwner {
  begin(
    nextDensity: GuideDensity,
    applyWorkflowValues: () => void,
  ): PendingSettingsGuideDensitySettlement;
}

export function createSettingsGuideDensitySettlementOwner(
  options: SettingsGuideDensitySettlementOwnerOptions,
): SettingsGuideDensitySettlementOwner {
  return {
    begin(nextDensity, applyWorkflowValues) {
      const polling = options.getPolling();
      const densityChanged = nextDensity !== options.getCurrentDensity();
      const densityRefreshWasPending = polling?.hasPendingGuideDensityChange() ?? false;
      if (densityChanged) {
        polling?.noteGuideDensityChange();
        options.retainGuideProgramFocusIntent();
      }
      applyWorkflowValues();

      let finished = false;
      return {
        densityChanged,
        finish(loading) {
          if (finished) return Promise.resolve();
          finished = true;
          if (!loading && (densityChanged || densityRefreshWasPending)) {
            options.restorePendingGuideFocus();
          }
          return polling?.settleGuideDensity(loading) ?? Promise.resolve();
        },
      };
    },
  };
}
