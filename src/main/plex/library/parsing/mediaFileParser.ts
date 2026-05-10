import type { PlexMediaFile, PlexMediaPart, RawMediaFile, RawMediaPart, RawStream } from '../types.js';
import { parseStream } from './streamParser.js';
import {
  parseArrayOrEmpty,
  parseRequiredObject,
  parseRequiredString,
  parseRequiredStringLike,
} from './parserValidation.js';

export function parseMediaFiles(mediaFiles: unknown): PlexMediaFile[] {
  return parseArrayOrEmpty<unknown>(mediaFiles, 'media file list').map((mediaFile, index) =>
    parseMediaFile(parseRequiredObject<RawMediaFile>(mediaFile, `media file list[${index}]`)),
  );
}

function parseMediaFile(data: RawMediaFile): PlexMediaFile {
  return {
    ...buildBaseMediaFile(data),
    parts: parseMediaParts(data.Part),
  };
}

function buildBaseMediaFile(data: RawMediaFile): Omit<PlexMediaFile, 'parts'> {
  const normalizedValues = normalizeMediaFileValues(data);

  return {
    id: parseRequiredStringLike(data.id, 'media file', 'id'),
    duration: data.duration ?? 0,
    bitrate: data.bitrate ?? 0,
    width: data.width ?? 0,
    height: data.height ?? 0,
    aspectRatio: data.aspectRatio ?? 0,
    videoCodec: normalizedValues.videoCodec,
    audioCodec: normalizedValues.audioCodec,
    audioChannels: data.audioChannels ?? 0,
    container: normalizedValues.container,
    videoResolution: data.videoResolution ?? '',
  };
}

function parseMediaPart(data: RawMediaPart): PlexMediaPart {
  const part: PlexMediaPart = {
    id: parseRequiredStringLike(data.id, 'media part', 'id'),
    key: parseRequiredString(data.key, 'media part', 'key'),
    duration: data.duration ?? 0,
    file: data.file ?? '',
    size: data.size ?? 0,
    container: data.container ?? '',
    streams: parseArrayOrEmpty<unknown>(data.Stream, 'media part streams').map((stream, index) =>
      parseStream(parseRequiredObject<RawStream>(stream, `media part streams[${index}]`)),
    ),
  };

  if (data.videoProfile !== undefined) {
    part.videoProfile = data.videoProfile;
  }

  if (data.audioProfile !== undefined) {
    part.audioProfile = data.audioProfile;
  }

  return part;
}

function parseMediaParts(parts: unknown): PlexMediaPart[] {
  return parseArrayOrEmpty<unknown>(parts, 'media file parts').map((part, index) =>
    parseMediaPart(parseRequiredObject<RawMediaPart>(part, `media file parts[${index}]`)),
  );
}

function normalizeMediaFileValues(data: RawMediaFile): {
  videoCodec: string;
  audioCodec: string;
  container: string;
} {
  return {
    videoCodec: (data.videoCodec ?? '').toLowerCase(),
    audioCodec: (data.audioCodec ?? '').toLowerCase(),
    container: (data.container ?? '').toLowerCase(),
  };
}
