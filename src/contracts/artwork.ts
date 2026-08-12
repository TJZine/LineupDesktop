export interface ArtworkRef {
  id: string;
  kind: 'poster' | 'background' | 'logo';
  expiresAtMs: number;
  altText: string;
  status: 'available' | 'placeholder';
}

export interface GuideArtworkSet {
  readonly poster: ArtworkRef | null;
  readonly background: ArtworkRef | null;
}

export const ARTWORK_REF_ID_PATTERN = /^artwork-[A-Za-z0-9_-]{16,96}$/u;

export function isSafeArtworkRefId(value: unknown): value is string {
  return typeof value === 'string' && ARTWORK_REF_ID_PATTERN.test(value);
}
