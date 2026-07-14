import type { FocusDirection } from '../navigation.js';

type Neighbors = Partial<Record<FocusDirection, string>>;

export function getStagedSetupNeighbors(
  focusId: string,
  documentRef: Document | null = typeof document === 'undefined' ? null : document,
): Neighbors | undefined {
  const owner = documentRef?.documentElement?.dataset.setupOwner;
  const enabled = visibleOwnerIds(documentRef);
  if (owner === 'custom-edit') {
    const editorIds = visibleOwnerIds(documentRef, '[data-staged-owner="custom-edit"]');
    if (editorIds.includes(focusId)) return linear(focusId, editorIds);
  }
  const present = (id: string, fallback: string): string => enabled.includes(id) ? id : fallback;
  if (focusId === 'setup-select-all') return { up: focusId, down: firstSection(enabled, 'setup-next'), left: focusId, right: present('setup-clear-all', focusId) };
  if (focusId === 'setup-clear-all') return { up: focusId, down: firstSection(enabled, 'setup-next'), left: present('setup-select-all', focusId), right: focusId };
  if (focusId.startsWith('plex-dyn-section-')) {
    const rows = enabled.filter((id) => id.startsWith('plex-dyn-section-'));
    const index = rows.indexOf(focusId);
    return { up: index > 0 ? rows[index - 1] : present('setup-select-all', focusId), down: index >= 0 && index < rows.length - 1 ? rows[index + 1] : present('setup-next', 'setup-back'), left: focusId, right: focusId };
  }
  if (focusId === 'setup-library-retry') return vertical(focusId, focusId, 'setup-back');
  if (focusId === 'setup-error-retry') return vertical(focusId, focusId, 'setup-error-back');
  if (focusId === 'setup-error-back') return vertical(focusId, 'setup-error-retry', focusId);
  if (focusId === 'setup-category-build') return { up: focusId, down: focusId, left: focusId, right: selectedMode(enabled, documentRef) };
  if (focusId.startsWith('channel-strategy-build-')) {
    const modes = ['channel-strategy-build-append', 'channel-strategy-build-replace', 'channel-strategy-build-custom'].filter((id) => enabled.includes(id));
    const index = modes.indexOf(focusId);
    return { up: modes[Math.max(0, index - 1)] ?? focusId, down: modes[index + 1] ?? 'setup-preview-toggle', left: 'setup-category-build', right: focusId };
  }
  if (focusId === 'setup-preview-toggle') return { up: 'channel-strategy-build-custom', down: present('setup-preview-retry', 'setup-next'), left: 'setup-category-build', right: focusId };
  if (focusId === 'setup-preview-retry') return vertical(focusId, 'setup-preview-toggle', 'setup-next');
  if (focusId === 'setup-replace-confirm') return vertical(focusId, focusId, 'setup-back');
  if (focusId === 'setup-next') return vertical(focusId, owner === 'preview' ? present('setup-preview-retry', 'setup-preview-toggle') : lastSection(enabled, 'setup-select-all'), 'setup-back');
  if (focusId === 'setup-back') return owner === 'build'
    ? vertical(focusId, present('setup-replace-confirm', focusId), 'setup-confirm')
    : vertical(focusId, owner === 'library' && enabled.includes('setup-library-retry') ? 'setup-library-retry' : 'setup-next');
  if (focusId === 'setup-confirm') return vertical(focusId, 'setup-back', focusId);
  if (focusId === 'setup-progress-cancel') return allSelf(focusId);
  if (focusId === 'setup-done') return vertical(focusId, focusId, present('setup-result-watch', focusId));
  if (focusId === 'setup-result-watch') return vertical(focusId, 'setup-done');
  if (focusId === 'custom-channel-name') return vertical(focusId, focusId, 'custom-channel-number');
  if (focusId === 'custom-channel-number') return vertical(focusId, 'custom-channel-name', 'custom-channel-save');
  if (focusId === 'custom-channel-save') return vertical(focusId, 'custom-channel-number', 'custom-channel-cancel');
  if (focusId === 'custom-channel-cancel') return vertical(focusId, 'custom-channel-save');
  if (focusId === 'custom-delete-cancel') return vertical(focusId, focusId, 'custom-delete-confirm');
  if (focusId === 'custom-delete-confirm') return vertical(focusId, 'custom-delete-cancel');
  if (focusId.startsWith('custom-channel-')) return linear(focusId, enabled.filter((id) => id.startsWith('custom-channel-')));
  return undefined;
}

function visibleOwnerIds(doc: Document | null, selector = '[data-focus-id]'): string[] {
  if (doc === null || typeof doc.querySelectorAll !== 'function') return [];
  const root = selector === '[data-focus-id]' ? doc : doc.querySelector<HTMLElement>(selector);
  if (root === null || typeof root.querySelectorAll !== 'function') return [];
  return Array.from(root.querySelectorAll<HTMLElement>('[data-focus-id]'))
    .filter((element) => element.closest('[hidden],[inert],[aria-hidden="true"]') === null && !(element as HTMLButtonElement).disabled && (typeof element.getAttribute !== 'function' || element.getAttribute('aria-disabled') !== 'true'))
    .map((element) => element.dataset.focusId).filter((id): id is string => id !== undefined);
}
function firstSection(ids: readonly string[], fallback: string): string { return ids.find((id) => id.startsWith('plex-dyn-section-')) ?? fallback; }
function lastSection(ids: readonly string[], fallback: string): string { return ids.filter((id) => id.startsWith('plex-dyn-section-')).at(-1) ?? fallback; }
function selectedMode(ids: readonly string[], doc: Document | null): string {
  const modes = ids.filter((id) => id.startsWith('channel-strategy-build-'));
  return modes.find((id) => {
    const element = doc?.querySelector<HTMLElement>(`[data-focus-id="${id}"]`);
    return element?.classList.contains('selected') === true || element?.getAttribute('aria-pressed') === 'true';
  }) ?? modes.find((id) => id === 'channel-strategy-build-append') ?? modes[0] ?? 'channel-strategy-build-append';
}
function linear(id: string, ids: readonly string[]): Neighbors | undefined { const i = ids.indexOf(id); return i < 0 ? undefined : vertical(id, ids[Math.max(0, i - 1)], ids[Math.min(ids.length - 1, i + 1)]); }
function vertical(id: string, up = id, down = id): Neighbors { return { up, down, left: id, right: id }; }
function allSelf(id: string): Neighbors { return { up: id, down: id, left: id, right: id }; }
