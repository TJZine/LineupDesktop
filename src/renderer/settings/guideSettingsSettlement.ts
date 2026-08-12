import type { DesktopSettingsValues } from '../../contracts/settings.js';

export type GuideSettingsValues = Pick<
  DesktopSettingsValues,
  'guideTimeRange' | 'guidePerformanceProfile' | 'guideRowDensity' | 'guideLayout'
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
  invalidateViewportLayout(): void;
  reconcileViewport(allowRefresh: boolean): void;
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
      const currentSettings = options.getCurrentSettings();
      const settingsChanged = !guideSettingsEqual(nextSettings, currentSettings);
      const presentationSettingsChanged = !guidePresentationSettingsEqual(nextSettings, currentSettings);
      const layoutChanged = nextSettings.guideLayout !== currentSettings.guideLayout;
      const densityChanged = nextSettings.guideRowDensity !== currentSettings.guideRowDensity;
      const settingsRefreshWasPending = polling?.hasPendingGuideSettingsChange() ?? false;
      if (presentationSettingsChanged) {
        polling?.noteGuideSettingsChange();
        options.retainGuideProgramFocusIntent();
      }
      if (layoutChanged || densityChanged) options.invalidateViewportLayout();
      applyWorkflowValues();

      let finished = false;
      return {
        settingsChanged,
        finish(loading) {
          if (finished) return Promise.resolve();
          finished = true;
          if (!loading && (layoutChanged || densityChanged)) {
            options.reconcileViewport(layoutChanged);
          }
          if (!loading && (presentationSettingsChanged || settingsRefreshWasPending)) {
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
    left.guideRowDensity === right.guideRowDensity &&
    left.guideLayout === right.guideLayout;
}

function guidePresentationSettingsEqual(left: GuideSettingsValues, right: GuideSettingsValues): boolean {
  return left.guideTimeRange === right.guideTimeRange &&
    left.guidePerformanceProfile === right.guidePerformanceProfile;
}
