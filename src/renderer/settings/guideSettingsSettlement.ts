import type { DesktopSettingsValues } from '../../contracts/settings.js';

export type GuideSettingsValues = Pick<
  DesktopSettingsValues,
  'guideTimeRange' | 'guidePerformanceProfile' | 'guideRowDensity'
>;

export interface GuideSettingsSettlementPolling {
  hasPendingGuideSettingsChange(): boolean;
  noteGuideSettingsChange(): void;
  settleGuideSettings(loading: boolean): Promise<void>;
}

export interface SettingsGuideSettingsSettlementOwnerOptions {
  getCurrentSettings(): GuideSettingsValues;
  getPolling(): GuideSettingsSettlementPolling | undefined;
  retainGuideProgramFocusIntent(): void;
  restorePendingGuideFocus(): void;
}

export interface PendingSettingsGuideSettingsSettlement {
  readonly settingsChanged: boolean;
  finish(loading: boolean): Promise<void>;
}

export interface SettingsGuideSettingsSettlementOwner {
  begin(
    nextSettings: GuideSettingsValues,
    applyWorkflowValues: () => void,
  ): PendingSettingsGuideSettingsSettlement;
}

export function createSettingsGuideSettingsSettlementOwner(
  options: SettingsGuideSettingsSettlementOwnerOptions,
): SettingsGuideSettingsSettlementOwner {
  return {
    begin(nextSettings, applyWorkflowValues) {
      const polling = options.getPolling();
      const settingsChanged = !guideSettingsEqual(nextSettings, options.getCurrentSettings());
      const settingsRefreshWasPending = polling?.hasPendingGuideSettingsChange() ?? false;
      if (settingsChanged) {
        polling?.noteGuideSettingsChange();
        options.retainGuideProgramFocusIntent();
      }
      applyWorkflowValues();

      let finished = false;
      return {
        settingsChanged,
        finish(loading) {
          if (finished) return Promise.resolve();
          finished = true;
          if (!loading && (settingsChanged || settingsRefreshWasPending)) {
            options.restorePendingGuideFocus();
          }
          return polling?.settleGuideSettings(loading) ?? Promise.resolve();
        },
      };
    },
  };
}

function guideSettingsEqual(left: GuideSettingsValues, right: GuideSettingsValues): boolean {
  return left.guideTimeRange === right.guideTimeRange &&
    left.guidePerformanceProfile === right.guidePerformanceProfile &&
    left.guideRowDensity === right.guideRowDensity;
}
