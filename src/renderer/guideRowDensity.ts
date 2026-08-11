import type { DesktopSettingsValues } from '../contracts/settings.js';

export type GuideRowDensity = DesktopSettingsValues['guideRowDensity'];
export type GuideRowDensityTreatment = Exclude<GuideRowDensity, 'auto'>;

export const GUIDE_COMFORTABLE_ROW_HEIGHT = 108;
export const GUIDE_COMPACT_ROW_HEIGHT = 72;
export const GUIDE_DEFAULT_ROW_GAP = 12;
export const GUIDE_MAX_COMPLETE_ROW_FLOOR = 20;
export const GUIDE_STANDARD_COMPLETE_ROW_FLOOR = 8;
export const GUIDE_MINIMUM_COMPLETE_ROW_FLOOR = 5;

export interface GuideViewportMetrics {
  /** CSS viewport dimensions used to classify the supported display envelope. */
  readonly width: number;
  readonly height: number;
  readonly devicePixelRatio?: number;
  /** Actual Guide grid space available for complete-row measurement. */
  readonly availableWidth?: number;
  readonly availableHeight?: number;
}

export interface GuideRowDensityResolution {
  readonly requested: GuideRowDensity;
  readonly effective: GuideRowDensityTreatment;
  readonly rowHeight: number;
  readonly rowGap: number;
  readonly rowOuterSize: number;
  readonly completeRows: number;
  readonly minimumCompleteRows: number;
  readonly floorMet: boolean;
}

export interface GuideCompleteRowInterval {
  readonly start: number;
  readonly count: number;
  /** Remaining schedule-row height after the unscrolled header/rail region. */
  readonly remainingHeight: number;
}

export function guideRowHeight(density: GuideRowDensityTreatment): number {
  return density === 'compact' ? GUIDE_COMPACT_ROW_HEIGHT : GUIDE_COMFORTABLE_ROW_HEIGHT;
}

export function completeGuideRowCount(
  viewportHeight: number,
  rowHeight: number,
  rowGap = 0,
): number {
  const height = nonNegativeFinite(viewportHeight);
  const normalizedRowHeight = positiveFinite(rowHeight, GUIDE_COMFORTABLE_ROW_HEIGHT);
  const normalizedGap = nonNegativeFinite(rowGap);
  if (height <= 0) return 0;
  return Math.max(0, Math.floor((height + normalizedGap) / (normalizedRowHeight + normalizedGap)));
}

export function projectGuideCompleteRowInterval(
  viewportHeight: number,
  rowStartOffset: number,
  scrollTop: number,
  rowHeight: number,
  rowGap = 0,
): GuideCompleteRowInterval {
  const normalizedViewportHeight = nonNegativeFinite(viewportHeight);
  const normalizedStartOffset = nonNegativeFinite(rowStartOffset);
  const normalizedScrollTop = nonNegativeFinite(scrollTop);
  const normalizedRowHeight = positiveFinite(rowHeight, GUIDE_COMFORTABLE_ROW_HEIGHT);
  const normalizedGap = nonNegativeFinite(rowGap);
  const rowOuterSize = normalizedRowHeight + normalizedGap;
  const remainingHeight = Math.max(
    0,
    normalizedViewportHeight - Math.max(0, normalizedStartOffset - normalizedScrollTop),
  );
  const relativeScrollTop = Math.max(0, normalizedScrollTop - normalizedStartOffset);
  const leadingPartialRow = relativeScrollTop % rowOuterSize;
  const start = leadingPartialRow > 0
    ? Math.ceil(relativeScrollTop / rowOuterSize)
    : Math.floor(relativeScrollTop / rowOuterSize);
  const firstCompleteOffset = leadingPartialRow > 0 ? rowOuterSize - leadingPartialRow : 0;
  const completeHeight = Math.max(0, remainingHeight - firstCompleteOffset);
  return {
    start: Math.max(0, start),
    count: completeGuideRowCount(completeHeight, normalizedRowHeight, normalizedGap),
    remainingHeight,
  };
}

export function guideCompleteRowFloor(viewport: GuideViewportMetrics): number {
  const scale = positiveFinite(viewport.devicePixelRatio ?? 1, 1);
  // The frozen floors are explicit 100%-scale envelopes. At 125/150% or
  // resized/narrow CSS surfaces, the applicable floor is the honest 5-row
  // minimum; do not reconstruct a physical 4K/1080 target from DPI.
  if (scale > 1.001) return GUIDE_MINIMUM_COMPLETE_ROW_FLOOR;
  if (viewport.width >= 3_840 && viewport.height >= 2_160) return GUIDE_MAX_COMPLETE_ROW_FLOOR;
  if (viewport.width >= 1_920 && viewport.height >= 1_080) return GUIDE_STANDARD_COMPLETE_ROW_FLOOR;
  return GUIDE_MINIMUM_COMPLETE_ROW_FLOOR;
}

export function resolveGuideRowDensity(
  requested: GuideRowDensity,
  viewport: GuideViewportMetrics,
  rowGap = 0,
): GuideRowDensityResolution {
  const normalizedGap = nonNegativeFinite(rowGap);
  const minimumCompleteRows = guideCompleteRowFloor(viewport);
  const availableHeight = positiveFinite(viewport.availableHeight ?? viewport.height, 0);
  const hasMeasuredHeight = viewport.availableHeight === undefined
    ? availableHeight > 0
    : Number.isFinite(viewport.availableHeight) && viewport.availableHeight > 0;
  const comfortableRows = completeGuideRowCount(availableHeight, GUIDE_COMFORTABLE_ROW_HEIGHT, normalizedGap);
  const compactRows = completeGuideRowCount(availableHeight, GUIDE_COMPACT_ROW_HEIGHT, normalizedGap);
  const effective = requested === 'comfortable' || requested === 'compact'
    ? requested
    : !hasMeasuredHeight
      ? 'comfortable'
      : comfortableRows >= minimumCompleteRows
        ? 'comfortable'
        : 'compact';
  const rowHeight = guideRowHeight(effective);
  const completeRows = effective === 'comfortable' ? comfortableRows : compactRows;
  return {
    requested,
    effective,
    rowHeight,
    rowGap: normalizedGap,
    rowOuterSize: rowHeight + normalizedGap,
    completeRows,
    minimumCompleteRows,
    floorMet: completeRows >= minimumCompleteRows,
  };
}

function nonNegativeFinite(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

function positiveFinite(value: number, fallback: number): number {
  return Number.isFinite(value) && value > 0 ? value : fallback;
}
