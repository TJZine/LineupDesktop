import type { PlexRuntimeRendererState } from '../plexRuntimeState.js';
import type { ChannelSetupLiveSelectionViewModel } from './viewModel.js';

export type ChannelSetupSelectedLibrary = ChannelSetupLiveSelectionViewModel & { id: string };

export function resolveChannelSetupLiveSelection(
  plexState: PlexRuntimeRendererState,
): ChannelSetupSelectedLibrary | null {
  const sectionId = plexState.selectedSectionId;
  if (sectionId === null) {
    return null;
  }
  const section = plexState.snapshot?.library.sections.find((candidate) => (
    candidate.id === sectionId &&
    (candidate.type === 'movie' || candidate.type === 'show')
  ));
  if (section === undefined) {
    return null;
  }
  if (section.type !== 'movie' && section.type !== 'show') {
    return null;
  }
  const library = plexState.snapshot?.library;
  const hasCurrentSectionItems = library?.selectedSectionId === section.id && library.search === null;
  return {
    id: section.id,
    sourceName: section.title,
    sourceType: section.type,
    contentCount: section.contentCount,
    loadedItemCount: hasCurrentSectionItems ? library.items.length : 0,
  };
}
