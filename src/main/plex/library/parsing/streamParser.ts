import type { PlexStream, RawStream } from '../types.js';
import {
  parseRequiredFiniteNumber,
  parseRequiredObject,
  parseRequiredString,
  parseRequiredStringLike,
} from './parserValidation.js';

const VALID_STREAM_TYPES = new Set([1, 2, 3]);
const TRUE_VALUES = new Set(['1', 'true', 'yes']);
const FALSE_VALUES = new Set(['0', 'false', 'no']);

export function parseStream(data: RawStream): PlexStream {
  const streamData = parseRequiredObject<RawStream>(data, 'stream');
  const stream: PlexStream = {
    id: parseRequiredStringLike(streamData.id, 'stream', 'id'),
    streamType: normalizeStreamType(
      parseRequiredFiniteNumber(streamData.streamType, 'stream', 'streamType'),
    ),
    codec: parseRequiredString(streamData.codec, 'stream', 'codec'),
  };

  assignOptionalStreamFields(stream, streamData);

  return stream;
}

function normalizeStreamType(value: number): 1 | 2 | 3 {
  return VALID_STREAM_TYPES.has(value) ? (value as 1 | 2 | 3) : 1;
}

function assignOptionalStreamFields(stream: PlexStream, data: RawStream): void {
  assignOptionalProperty(stream, 'language', data.language);
  assignOptionalProperty(stream, 'languageCode', data.languageCode);
  assignOptionalProperty(stream, 'title', data.title);
  assignOptionalProperty(stream, 'displayTitle', data.displayTitle);
  assignOptionalProperty(stream, 'extendedDisplayTitle', data.extendedDisplayTitle);
  assignOptionalProperty(stream, 'selected', data.selected);
  assignOptionalProperty(stream, 'default', data.default);
  assignOptionalProperty(stream, 'forced', data.forced);
  assignOptionalProperty(stream, 'width', data.width);
  assignOptionalProperty(stream, 'height', data.height);
  assignOptionalProperty(stream, 'bitrate', data.bitrate);
  assignOptionalProperty(stream, 'frameRate', data.frameRate);
  assignOptionalProperty(stream, 'channels', data.channels);
  assignOptionalProperty(stream, 'samplingRate', data.samplingRate);
  assignOptionalProperty(stream, 'format', data.format);
  assignOptionalProperty(stream, 'key', data.key);
  assignOptionalProperty(stream, 'profile', data.profile);
  assignOptionalProperty(stream, 'colorTrc', data.colorTrc);
  assignOptionalProperty(stream, 'colorSpace', data.colorSpace);
  assignOptionalProperty(stream, 'colorPrimaries', data.colorPrimaries);
  assignOptionalProperty(stream, 'bitDepth', data.bitDepth);
  assignOptionalProperty(stream, 'hdr', data.hdr);
  assignOptionalProperty(stream, 'dynamicRange', data.dynamicRange);

  if (data.DOVIProfile !== undefined) {
    stream.doviProfile = String(data.DOVIProfile);
  }

  const doviPresent = normalizeOptionalBoolean(data.DOVIPresent);
  if (typeof doviPresent === 'boolean') {
    stream.doviPresent = doviPresent;
  }
}

function assignOptionalProperty<K extends keyof PlexStream>(
  stream: PlexStream,
  key: K,
  value: PlexStream[K] | undefined,
): void {
  if (value !== undefined) {
    stream[key] = value;
  }
}

function normalizeOptionalBoolean(value: unknown): boolean | undefined {
  if (typeof value === 'boolean') {
    return value;
  }

  if (typeof value === 'number') {
    return value > 0;
  }

  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (TRUE_VALUES.has(normalized)) {
      return true;
    }
    if (FALSE_VALUES.has(normalized)) {
      return false;
    }
  }

  return undefined;
}
