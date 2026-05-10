export type PlexMediaType = 'movie' | 'show' | 'episode' | 'track' | 'clip';

export type PlexLibrarySectionType = 'movie' | 'show' | 'artist' | 'photo';

export interface PlexLibrarySection {
  id: string;
  uuid: string;
  title: string;
  type: PlexLibrarySectionType;
  agent: string;
  scanner: string;
  contentCount: number | null;
  episodeCount?: number;
  lastScannedAt: Date;
  art: string | null;
  thumb: string | null;
}

export interface PlexStream {
  id: string;
  streamType: 1 | 2 | 3;
  codec: string;
  language?: string;
  languageCode?: string;
  title?: string;
  displayTitle?: string;
  extendedDisplayTitle?: string;
  selected?: boolean;
  default?: boolean;
  forced?: boolean;
  width?: number;
  height?: number;
  bitrate?: number;
  frameRate?: number;
  channels?: number;
  samplingRate?: number;
  format?: string;
  key?: string;
  profile?: string;
  colorTrc?: string;
  colorSpace?: string;
  colorPrimaries?: string;
  bitDepth?: number;
  hdr?: string;
  dynamicRange?: string;
  doviProfile?: string;
  doviPresent?: boolean;
}

export interface PlexMediaPart {
  id: string;
  key: string;
  duration: number;
  file: string;
  size: number;
  container: string;
  videoProfile?: string;
  audioProfile?: string;
  streams: PlexStream[];
}

export interface PlexMediaFile {
  id: string;
  duration: number;
  bitrate: number;
  width: number;
  height: number;
  aspectRatio: number;
  videoCodec: string;
  audioCodec: string;
  audioChannels: number;
  container: string;
  videoResolution: string;
  parts: PlexMediaPart[];
}

export interface PlexMediaRole {
  name: string;
  role?: string | null;
  thumb?: string | null;
}

export interface PlexMediaItem {
  ratingKey: string;
  key: string;
  type: PlexMediaType;
  title: string;
  originalTitle?: string;
  sortTitle: string;
  summary: string;
  year: number;
  durationMs: number;
  addedAt: Date;
  updatedAt: Date;
  thumb: string | null;
  art: string | null;
  banner?: string | null;
  clearLogo?: string | null;
  rating?: number;
  audienceRating?: number;
  contentRating?: string;
  genres?: string[];
  directors?: string[];
  actors?: string[];
  studios?: string[];
  actorRoles?: PlexMediaRole[];
  grandparentTitle?: string;
  parentTitle?: string;
  grandparentThumb?: string | null;
  parentThumb?: string | null;
  seasonNumber?: number;
  episodeNumber?: number;
  viewOffset?: number;
  viewCount?: number;
  lastViewedAt?: Date;
  grandparentRatingKey?: string;
  parentRatingKey?: string;
  media: PlexMediaFile[];
}

export interface PlexSeason {
  ratingKey: string;
  key: string;
  title: string;
  index: number;
  leafCount: number;
  viewedLeafCount: number;
  thumb: string | null;
}

export interface PlexCollection {
  ratingKey: string;
  key: string;
  title: string;
  thumb: string | null;
  childCount: number;
}

export interface PlexPlaylist {
  ratingKey: string;
  key: string;
  title: string;
  thumb: string | null;
  duration: number;
  leafCount: number;
}

export interface PlexTagDirectoryItem {
  key: string;
  title: string;
  count: number | null;
  fastKey?: string;
  thumb?: string;
}

export type PlexLibraryRequestIntent = 'preview' | 'background';

export interface LibraryQueryOptions {
  sort?: string;
  filter?: Readonly<Record<string, string | number>>;
  offset?: number;
  limit?: number;
  includeCollections?: boolean;
  signal?: AbortSignal | null;
}

export interface SearchOptions {
  types?: PlexMediaType[];
  libraryId?: string;
  limit?: number;
  signal?: AbortSignal | null;
}

export interface PlexMediaContainer<T> {
  MediaContainer: {
    size?: number;
    totalSize?: number;
    offset?: number;
    Directory?: T[];
    Metadata?: T[];
    Hub?: PlexSearchHub[];
  };
}

export interface PlexSearchHub {
  type: string;
  hubIdentifier?: string;
  size?: number;
  title?: string;
  Metadata?: RawMediaItem[];
}

export interface RawLibrarySection {
  key: string;
  uuid: string;
  title: string;
  type: string;
  agent: string;
  scanner: string;
  art?: string;
  thumb?: string;
  updatedAt?: number;
  scannedAt?: number;
}

export interface RawMediaItem {
  ratingKey: string;
  key: string;
  type: string;
  title: string;
  originalTitle?: string;
  titleSort?: string;
  summary?: string;
  year?: number;
  duration?: number;
  addedAt?: number;
  updatedAt?: number;
  thumb?: string;
  art?: string;
  banner?: string;
  rating?: number;
  audienceRating?: number;
  contentRating?: string;
  Genre?: RawTag[];
  Director?: RawTag[];
  Role?: RawRole[];
  Studio?: RawTag[];
  Image?: RawImage[];
  grandparentTitle?: string;
  parentTitle?: string;
  grandparentThumb?: string | null;
  parentThumb?: string | null;
  parentIndex?: number;
  index?: number;
  viewOffset?: number;
  viewCount?: number;
  lastViewedAt?: number;
  grandparentRatingKey?: string;
  parentRatingKey?: string;
  Media?: RawMediaFile[];
}

export interface RawImage {
  alt?: string;
  type?: string;
  url?: string;
}

export interface RawTag {
  id?: number;
  tag?: string;
}

export interface RawRole {
  id?: number;
  tag?: string;
  role?: string;
  thumb?: string;
}

export interface RawMediaFile {
  id: string | number;
  duration?: number;
  bitrate?: number;
  width?: number;
  height?: number;
  aspectRatio?: number;
  videoCodec?: string;
  audioCodec?: string;
  audioChannels?: number;
  container?: string;
  videoResolution?: string;
  Part?: RawMediaPart[];
}

export interface RawMediaPart {
  id: string | number;
  key: string;
  duration?: number;
  file?: string;
  size?: number;
  container?: string;
  videoProfile?: string;
  audioProfile?: string;
  Stream?: RawStream[];
}

export interface RawStream {
  id: string | number;
  streamType: number;
  codec: string;
  language?: string;
  languageCode?: string;
  title?: string;
  displayTitle?: string;
  extendedDisplayTitle?: string;
  selected?: boolean;
  default?: boolean;
  forced?: boolean;
  width?: number;
  height?: number;
  bitrate?: number;
  frameRate?: number;
  channels?: number;
  samplingRate?: number;
  format?: string;
  key?: string;
  profile?: string;
  colorTrc?: string;
  colorSpace?: string;
  colorPrimaries?: string;
  bitDepth?: number;
  hdr?: string;
  dynamicRange?: string;
  DOVIProfile?: string | number;
  DOVIPresent?: boolean | number | string;
}

export interface RawSeason {
  ratingKey: string;
  key: string;
  title: string;
  index?: number;
  leafCount?: number;
  viewedLeafCount?: number;
  thumb?: string;
}

export interface RawCollection {
  ratingKey: string;
  key: string;
  title: string;
  thumb?: string;
  childCount?: number;
}

export interface RawPlaylist {
  ratingKey: string;
  key: string;
  title: string;
  thumb?: string;
  duration?: number;
  leafCount?: number;
}

export interface RawDirectoryTag {
  key: string;
  title: string;
  count?: number | string;
  fastKey?: string;
  thumb?: string;
}
