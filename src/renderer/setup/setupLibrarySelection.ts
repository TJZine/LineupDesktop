import type { PlexLibrarySectionSummary } from '../../contracts/plex.js';

export const SETUP_LIBRARY_LIMIT = 24;

export type SetupLibrarySection = Pick<PlexLibrarySectionSummary, 'id' | 'type'>;

export interface SetupLibrarySelectionResult {
  selectedSectionIds: readonly string[];
  limitReached: boolean;
}

export function eligibleSetupLibraries(
  sections: readonly PlexLibrarySectionSummary[],
): readonly PlexLibrarySectionSummary[] {
  return sections.filter((section) => section.type === 'movie' || section.type === 'show');
}

export function normalizeSetupLibrarySelection(
  selectedSectionIds: readonly string[],
  sections: readonly SetupLibrarySection[],
): readonly string[] {
  const selected = new Set(selectedSectionIds);
  const normalized: string[] = [];
  for (const section of sections) {
    if (
      normalized.length >= SETUP_LIBRARY_LIMIT
      || (section.type !== 'movie' && section.type !== 'show')
      || !selected.has(section.id)
      || normalized.includes(section.id)
    ) continue;
    normalized.push(section.id);
  }
  return normalized;
}

export function toggleSetupLibrarySelection(
  selectedSectionIds: readonly string[],
  sectionId: string,
  sections: readonly SetupLibrarySection[],
): SetupLibrarySelectionResult {
  const normalized = normalizeSetupLibrarySelection(selectedSectionIds, sections);
  if (normalized.includes(sectionId)) {
    return {
      selectedSectionIds: normalized.filter((id) => id !== sectionId),
      limitReached: false,
    };
  }
  const eligible = sections.some((section) => (
    section.id === sectionId && (section.type === 'movie' || section.type === 'show')
  ));
  if (!eligible || normalized.length >= SETUP_LIBRARY_LIMIT) {
    return { selectedSectionIds: normalized, limitReached: eligible };
  }
  return {
    selectedSectionIds: normalizeSetupLibrarySelection([...normalized, sectionId], sections),
    limitReached: false,
  };
}

export function selectAllSetupLibraries(
  sections: readonly SetupLibrarySection[],
): SetupLibrarySelectionResult {
  const eligibleIds = sections
    .filter((section) => section.type === 'movie' || section.type === 'show')
    .map((section) => section.id);
  return {
    selectedSectionIds: eligibleIds.slice(0, SETUP_LIBRARY_LIMIT),
    limitReached: eligibleIds.length > SETUP_LIBRARY_LIMIT,
  };
}

export function clearSetupLibrarySelection(): SetupLibrarySelectionResult {
  return { selectedSectionIds: [], limitReached: false };
}

export function resolveSetupPreviewCursor(
  selectedSectionIds: readonly string[],
  currentCursor: string | null,
): string | null {
  if (currentCursor !== null && selectedSectionIds.includes(currentCursor)) return currentCursor;
  return selectedSectionIds[0] ?? currentCursor;
}
