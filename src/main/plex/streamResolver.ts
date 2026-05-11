import type {
  PlayerError,
  PlayerLoadCommandPayload,
  PlayerMediaSummary,
  PlayerRendererSafeDiagnostic,
  PlayerRequestId,
  PlayerSubtitleDeliveryMode,
  PlayerTrackId,
} from '../../contracts/player.js';
import { decideDesktopStreamPolicy } from '../player/streamPolicy/desktopStreamPolicy.js';
import type {
  DesktopStreamCapabilityProfile,
  DesktopStreamDynamicRange,
  DesktopStreamMediaCandidate,
  DesktopStreamPolicyDecision,
} from '../player/streamPolicy/types.js';
import type { PlexConnection } from './discovery/types.js';
import type { PlexMediaFile, PlexMediaItem, PlexMediaPart, PlexStream } from './library/types.js';

export interface PlexStreamResolverSelectedConnectionPort {
  getSelectedConnection(): Promise<PlexConnection | null>;
}

export interface PlexStreamResolverActiveCredentialPort {
  getActiveAuthHeader(): Promise<PlexStreamResolverAuthHeader | null>;
}

export interface PlexStreamResolverAuthHeader {
  name: string;
  value: string;
}

export interface PlexStreamResolverMediaDetailPort {
  getMediaDetail(input: { mediaId: string }): Promise<PlexMediaItem | null>;
}

export interface PlexStreamResolverPmsSessionLease {
  id: string;
  requestId: PlayerRequestId;
}

export interface PlexStreamResolverPmsSessionPort {
  startSession(input: PlexStreamResolverPmsSessionStartInput): Promise<PlexStreamResolverPmsSessionLease | null>;
}

export interface PlexStreamResolverPmsSessionStartInput {
  requestId: PlayerRequestId;
  media: Pick<PlayerMediaSummary, 'id' | 'title'>;
  decisionKind: DesktopStreamPolicyDecision['kind'];
  connection: Pick<PlexConnection, 'protocol' | 'address' | 'port' | 'local' | 'relay'>;
}

export interface PlexStreamResolverOptions {
  selectedConnection: PlexStreamResolverSelectedConnectionPort;
  activeCredential: PlexStreamResolverActiveCredentialPort;
  mediaDetail: PlexStreamResolverMediaDetailPort;
  pmsSession?: PlexStreamResolverPmsSessionPort;
}

export interface PlexStreamResolverInput {
  requestId: PlayerRequestId;
  mediaId: string;
  capabilityProfile: DesktopStreamCapabilityProfile;
  autoplay?: boolean;
  startPositionMs?: number;
  preferredAudioTrackId?: PlayerTrackId | null;
  preferredSubtitleTrackId?: PlayerTrackId | null;
}

export type PlexStreamResolverResult =
  | {
      ok: true;
      privatePlayback: PlexPrivilegedPlaybackDescriptor;
      load: PlayerLoadCommandPayload;
      decision: DesktopStreamPolicyDecision;
      pmsSession: PlexStreamResolverPmsSessionLease | null;
      diagnostics: readonly PlayerRendererSafeDiagnostic[];
    }
  | {
      ok: false;
      error: PlayerError;
      decision?: DesktopStreamPolicyDecision;
      diagnostics: readonly PlayerRendererSafeDiagnostic[];
    };

export interface PlexPrivilegedPlaybackDescriptor {
  requestId: PlayerRequestId;
  decisionKind: Exclude<DesktopStreamPolicyDecision['kind'], 'unsupported'>;
  playbackUrl: string;
  credentialHeader: PlexStreamResolverAuthHeader;
  selectedConnection: {
    protocol: PlexConnection['protocol'];
    address: string;
    port: number;
    local: boolean;
    relay: boolean;
  };
  media: Pick<PlayerMediaSummary, 'id' | 'title'>;
  setup: {
    playbackMode: Exclude<DesktopStreamPolicyDecision['kind'], 'unsupported'>;
    mediaPath: string;
    variantId: string;
    partPath: string;
    selectedTrackIds: DesktopStreamPolicyDecision['selectedTrackIds'];
    selectedPrivateTrackIds: {
      video: string | null;
      audio: string | null;
      subtitle: string | null;
    };
  };
}

export class PlexStreamResolver {
  readonly #selectedConnection: PlexStreamResolverSelectedConnectionPort;
  readonly #activeCredential: PlexStreamResolverActiveCredentialPort;
  readonly #mediaDetail: PlexStreamResolverMediaDetailPort;
  readonly #pmsSession?: PlexStreamResolverPmsSessionPort;

  constructor(options: PlexStreamResolverOptions) {
    this.#selectedConnection = options.selectedConnection;
    this.#activeCredential = options.activeCredential;
    this.#mediaDetail = options.mediaDetail;
    this.#pmsSession = options.pmsSession;
  }

  async resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult> {
    const diagnostics: PlayerRendererSafeDiagnostic[] = [];
    const connection = await this.#getSelectedConnection(input.requestId, diagnostics);
    if (connection === null) {
      return this.#failure(input.requestId, 'PLEX_STREAM_CONNECTION_UNAVAILABLE', 'source', 'selected connection unavailable', diagnostics);
    }
    if (!isUsableConnection(connection)) {
      return this.#failure(input.requestId, 'PLEX_STREAM_CONNECTION_UNAVAILABLE', 'source', 'selected connection unavailable', diagnostics);
    }

    const authHeader = await this.#getActiveAuthHeader(input.requestId, diagnostics);
    if (authHeader === null) {
      return this.#failure(input.requestId, 'PLEX_STREAM_CREDENTIAL_UNAVAILABLE', 'authentication', 'active credential unavailable', diagnostics);
    }
    if (!isUsableAuthHeader(authHeader)) {
      return this.#failure(input.requestId, 'PLEX_STREAM_CREDENTIAL_UNAVAILABLE', 'authentication', 'active credential unavailable', diagnostics);
    }

    const mediaDetail = await this.#getMediaDetail(input.requestId, input.mediaId, diagnostics);
    if (mediaDetail === null) {
      return this.#failure(input.requestId, 'PLEX_STREAM_MEDIA_UNAVAILABLE', 'source', 'media detail unavailable', diagnostics);
    }

    const candidates = mapPlexMediaDetailsToDesktopStreamCandidates(mediaDetail);
    diagnostics.push({
      component: 'plex-stream-resolver',
      operation: 'policy.evaluate',
      status: candidates.length > 0 ? 'evaluated' : 'rejected',
      counts: { candidates: candidates.length },
      media: { id: toPlayerMediaId(mediaDetail), title: mediaDetail.title },
      capabilityProfileId: input.capabilityProfile.id,
    });

    const decision = decideDesktopStreamPolicy({
      capabilityProfile: input.capabilityProfile,
      candidates,
      preferredAudioTrackId: input.preferredAudioTrackId,
      preferredSubtitleTrackId: input.preferredSubtitleTrackId,
    });

    if (decision.kind === 'unsupported' || decision.candidateId === null) {
      return this.#failure(
        input.requestId,
        'PLEX_STREAM_UNSUPPORTED_MEDIA',
        'unsupported-media',
        'stream policy rejected media',
        diagnostics,
        decision,
      );
    }

    const selected = candidates.find((candidate) => candidate.candidateId === decision.candidateId);
    const selectedPrivate = findSelectedPrivatePart(mediaDetail, selected);
    if (selected === undefined || selectedPrivate === null) {
      return this.#failure(
        input.requestId,
        'PLEX_STREAM_MEDIA_INVALID',
        'validation-failure',
        'selected media part unavailable',
        diagnostics,
        decision,
      );
    }

    const load = projectPlayerLoadPayload({
      candidate: selected,
      decision,
      capabilityProfileId: input.capabilityProfile.id,
      autoplay: input.autoplay ?? true,
      startPositionMs: input.startPositionMs,
    });

    const privatePlayback = buildPrivatePlaybackDescriptor({
      requestId: input.requestId,
      decision,
      connection,
      authHeader,
      mediaDetail,
      candidate: selected,
      selectedPart: selectedPrivate,
    });

    const pmsSession = await this.#startSession(input.requestId, load.media, decision.kind, connection, diagnostics);
    diagnostics.push({
      component: 'plex-stream-resolver',
      operation: 'stream.resolve',
      status: 'resolved',
      reason: decision.kind,
      media: { id: load.media.id, title: load.media.title },
      capabilityProfileId: input.capabilityProfile.id,
      trackIds: compactTrackIds(decision.selectedTrackIds),
    });

    return { ok: true, privatePlayback, load, decision, pmsSession, diagnostics };
  }

  async #getSelectedConnection(
    requestId: PlayerRequestId,
    diagnostics: PlayerRendererSafeDiagnostic[],
  ): Promise<PlexConnection | null> {
    try {
      return await this.#selectedConnection.getSelectedConnection();
    } catch {
      diagnostics.push(createPortFailureDiagnostic(requestId, 'selected-connection.read'));
      return null;
    }
  }

  async #getActiveAuthHeader(
    requestId: PlayerRequestId,
    diagnostics: PlayerRendererSafeDiagnostic[],
  ): Promise<PlexStreamResolverAuthHeader | null> {
    try {
      return await this.#activeCredential.getActiveAuthHeader();
    } catch {
      diagnostics.push(createPortFailureDiagnostic(requestId, 'active-credential.read'));
      return null;
    }
  }

  async #getMediaDetail(
    requestId: PlayerRequestId,
    mediaId: string,
    diagnostics: PlayerRendererSafeDiagnostic[],
  ): Promise<PlexMediaItem | null> {
    try {
      return await this.#mediaDetail.getMediaDetail({ mediaId });
    } catch {
      diagnostics.push(createPortFailureDiagnostic(requestId, 'media-detail.read'));
      return null;
    }
  }

  async #startSession(
    requestId: PlayerRequestId,
    media: PlayerMediaSummary,
    decisionKind: DesktopStreamPolicyDecision['kind'],
    connection: PlexConnection,
    diagnostics: PlayerRendererSafeDiagnostic[],
  ): Promise<PlexStreamResolverPmsSessionLease | null> {
    if (this.#pmsSession === undefined) {
      return null;
    }
    try {
      return await this.#pmsSession.startSession({
        requestId,
        media: { id: media.id, title: media.title },
        decisionKind,
        connection: projectConnection(connection),
      });
    } catch {
      diagnostics.push({
        component: 'plex-stream-resolver',
        operation: 'pms-session.start',
        status: 'failed',
        reason: 'session start failed',
        media: { id: media.id, title: media.title },
      });
      return null;
    }
  }

  #failure(
    requestId: PlayerRequestId,
    code: string,
    category: PlayerError['category'],
    reason: string,
    diagnostics: readonly PlayerRendererSafeDiagnostic[],
    decision?: DesktopStreamPolicyDecision,
  ): Extract<PlexStreamResolverResult, { ok: false }> {
    const diagnostic: PlayerRendererSafeDiagnostic = {
      component: 'plex-stream-resolver',
      operation: 'stream.resolve',
      status: 'failed',
      reason,
    };
    return {
      ok: false,
      ...(decision !== undefined ? { decision } : {}),
      diagnostics: [...diagnostics, diagnostic],
      error: {
        code,
        category,
        message: 'The Plex stream resolver could not prepare media for playback.',
        recoverable: category !== 'validation-failure',
        retryable: category === 'source' || category === 'network',
        requestId,
        diagnostic,
      },
    };
  }
}

export function mapPlexMediaDetailsToDesktopStreamCandidates(
  mediaDetail: PlexMediaItem,
): readonly DesktopStreamMediaCandidate[] {
  const mediaSummary = toPlayerMediaSummary(mediaDetail);
  return mediaDetail.media.flatMap((variant, variantIndex) => {
    return variant.parts.map((part, partIndex) => {
      const trackScope = createTrackIdScope(variantIndex, partIndex);
      const video = selectVideoStream(part, variant, trackScope);
      return {
        candidateId: toCandidateId(variant, part),
        media: {
          ...mediaSummary,
          container: part.container || variant.container || mediaSummary.container,
          durationMs: part.duration || variant.duration || mediaSummary.durationMs,
        },
        variant: {
          id: toVariantId(variant),
          container: part.container || variant.container || null,
          durationMs: variant.duration || null,
        },
        part: {
          id: toPartId(part),
          durationMs: part.duration || null,
        },
        video,
        audioTracks: mapAudioTracks(part, variant, trackScope),
        subtitleTracks: mapSubtitleTracks(part, trackScope),
      };
    });
  });
}

function projectPlayerLoadPayload(input: {
  candidate: DesktopStreamMediaCandidate;
  decision: DesktopStreamPolicyDecision;
  capabilityProfileId: string;
  autoplay: boolean;
  startPositionMs?: number;
}): PlayerLoadCommandPayload {
  const policy: PlayerLoadCommandPayload['policy'] = {
    autoplay: input.autoplay,
    preferredAudioTrackId: input.decision.selectedTrackIds.audio,
    preferredSubtitleTrackId: input.decision.selectedTrackIds.subtitle,
  };
  if (input.startPositionMs !== undefined) {
    policy.startPositionMs = input.startPositionMs;
  }
  return {
    media: input.candidate.media,
    policy,
    capabilityProfileId: input.capabilityProfileId,
  };
}

function buildPrivatePlaybackDescriptor(input: {
  requestId: PlayerRequestId;
  decision: DesktopStreamPolicyDecision;
  connection: PlexConnection;
  authHeader: PlexStreamResolverAuthHeader;
  mediaDetail: PlexMediaItem;
  candidate: DesktopStreamMediaCandidate;
  selectedPart: PlexMediaPart;
}): PlexPrivilegedPlaybackDescriptor {
  return {
    requestId: input.requestId,
    decisionKind: input.decision.kind as Exclude<DesktopStreamPolicyDecision['kind'], 'unsupported'>,
    playbackUrl: buildPlaybackUrl(input.connection, input.decision.kind, input.selectedPart),
    credentialHeader: { ...input.authHeader },
    selectedConnection: projectConnection(input.connection),
    media: { id: toPlayerMediaId(input.mediaDetail), title: input.mediaDetail.title },
    setup: {
      playbackMode: input.decision.kind as Exclude<DesktopStreamPolicyDecision['kind'], 'unsupported'>,
      mediaPath: input.mediaDetail.key,
      variantId: input.candidate.variant.id,
      partPath: input.selectedPart.key,
      selectedTrackIds: input.decision.selectedTrackIds,
      selectedPrivateTrackIds: mapSelectedPrivateTrackIds(input.selectedPart, input.candidate, input.decision),
    },
  };
}

function buildPlaybackUrl(
  connection: PlexConnection,
  decisionKind: DesktopStreamPolicyDecision['kind'],
  part: PlexMediaPart,
): string {
  const base = connection.uri.replace(/\/+$/u, '');
  if (decisionKind === 'transcode') {
    const path = encodeURIComponent(part.key);
    return `${base}/video/:/transcode/universal/start?path=${path}&protocol=hls`;
  }
  if (decisionKind === 'direct-stream') {
    const path = encodeURIComponent(part.key);
    return `${base}/video/:/transcode/universal/start?path=${path}&protocol=hls&directStream=1`;
  }
  return `${base}${part.key.startsWith('/') ? part.key : `/${part.key}`}`;
}

function findSelectedPrivatePart(
  mediaDetail: PlexMediaItem,
  candidate: DesktopStreamMediaCandidate | undefined,
): PlexMediaPart | null {
  if (candidate === undefined) {
    return null;
  }
  for (const variant of mediaDetail.media) {
    for (const part of variant.parts) {
      if (toCandidateId(variant, part) === candidate.candidateId) {
        return part;
      }
    }
  }
  return null;
}

function toPlayerMediaSummary(media: PlexMediaItem): PlayerMediaSummary {
  return {
    id: toPlayerMediaId(media),
    title: media.title,
    ...(media.parentTitle !== undefined ? { subtitle: media.parentTitle } : {}),
    durationMs: media.durationMs,
    container: media.media[0]?.container,
  };
}

function toPlayerMediaId(media: PlexMediaItem): string {
  return `plex-media-${media.ratingKey}`;
}

function toCandidateId(variant: PlexMediaFile, part: PlexMediaPart): string {
  return `plex-candidate-${variant.id}-${part.id}`;
}

function toVariantId(variant: PlexMediaFile): string {
  return `plex-variant-${variant.id}`;
}

function toPartId(part: PlexMediaPart): string {
  return `plex-part-${part.id}`;
}

function selectVideoStream(
  part: PlexMediaPart,
  variant: PlexMediaFile,
  trackScope: TrackIdScope,
): DesktopStreamMediaCandidate['video'] {
  const stream = part.streams.find((candidate) => candidate.streamType === 1);
  return {
    id: toTrackId(trackScope, 'video', 0),
    codec: stream?.codec ?? variant.videoCodec ?? null,
    dynamicRange: mapDynamicRange(stream),
    ...(stream?.width !== undefined || variant.width !== undefined
      ? { width: stream?.width ?? variant.width }
      : {}),
    ...(stream?.height !== undefined || variant.height !== undefined
      ? { height: stream?.height ?? variant.height }
      : {}),
  };
}

function mapAudioTracks(
  part: PlexMediaPart,
  variant: PlexMediaFile,
  trackScope: TrackIdScope,
): DesktopStreamMediaCandidate['audioTracks'] {
  const streams = part.streams.filter((candidate) => candidate.streamType === 2);
  if (streams.length === 0 && variant.audioCodec) {
    return [
      {
        id: toTrackId(trackScope, 'audio', 0),
        label: labelTrack('Audio', variant.audioCodec, undefined),
        codec: variant.audioCodec,
        channelCount: variant.audioChannels,
        default: true,
      },
    ];
  }
  return streams.map((stream, index) => ({
    id: toTrackId(trackScope, 'audio', index),
    label: labelTrack('Audio', stream.displayTitle ?? stream.title ?? stream.codec, stream.language),
    ...(stream.languageCode !== undefined || stream.language !== undefined
      ? { language: stream.languageCode ?? stream.language }
      : {}),
    codec: stream.codec,
    ...(stream.channels !== undefined ? { channelCount: stream.channels } : {}),
    default: stream.default === true || (stream.selected === true && index === 0),
  }));
}

function mapSubtitleTracks(
  part: PlexMediaPart,
  trackScope: TrackIdScope,
): DesktopStreamMediaCandidate['subtitleTracks'] {
  return part.streams
    .filter((candidate) => candidate.streamType === 3)
    .map((stream, index) => ({
      id: toTrackId(trackScope, 'subtitle', index),
      label: labelTrack('Subtitle', stream.displayTitle ?? stream.title ?? stream.codec, stream.language),
      ...(stream.languageCode !== undefined || stream.language !== undefined
        ? { language: stream.languageCode ?? stream.language }
        : {}),
      delivery: mapSubtitleDelivery(stream),
      ...(stream.format !== undefined ? { format: stream.format } : {}),
      forced: stream.forced === true,
      default: stream.default === true || stream.selected === true,
    }));
}

function mapSubtitleDelivery(stream: PlexStream): PlayerSubtitleDeliveryMode {
  const format = (stream.format ?? stream.codec).toLowerCase();
  if (format === 'unknown') {
    return 'unknown';
  }
  if (format === 'pgs' || format === 'vobsub') {
    return 'embedded';
  }
  if (format === 'ass' || format === 'ssa' || format === 'srt' || format === 'webvtt') {
    return stream.key ? 'sidecar' : 'embedded';
  }
  return stream.key ? 'external' : 'embedded';
}

function mapDynamicRange(stream: PlexStream | undefined): DesktopStreamDynamicRange {
  if (stream === undefined) {
    return 'unknown';
  }
  if (stream.doviPresent === true || stream.doviProfile !== undefined) {
    return 'dolby-vision';
  }
  const facts = [stream.dynamicRange, stream.hdr, stream.colorTrc, stream.colorSpace, stream.colorPrimaries]
    .filter((value): value is string => value !== undefined)
    .map((value) => value.toLowerCase());
  if (facts.some((value) => value.includes('dolby') || value.includes('dovi'))) {
    return 'dolby-vision';
  }
  if (facts.some((value) => value.includes('hdr') || value.includes('bt2020') || value.includes('smpte'))) {
    return 'hdr10';
  }
  if (facts.length === 0) {
    return 'unknown';
  }
  return 'sdr';
}

function labelTrack(prefix: string, detail: string | undefined, language: string | undefined): string {
  const parts = [prefix, detail, language].filter((value): value is string => value !== undefined && value.trim() !== '');
  return parts.join(' ');
}

interface TrackIdScope {
  variantIndex: number;
  partIndex: number;
}

function createTrackIdScope(variantIndex: number, partIndex: number): TrackIdScope {
  return { variantIndex, partIndex };
}

function toTrackId(scope: TrackIdScope, kind: 'audio' | 'subtitle' | 'video', trackIndex: number): PlayerTrackId {
  return `plex-track-${kind}-${scope.variantIndex + 1}-${scope.partIndex + 1}-${trackIndex + 1}`;
}

function mapSelectedPrivateTrackIds(
  part: PlexMediaPart,
  candidate: DesktopStreamMediaCandidate,
  decision: DesktopStreamPolicyDecision,
): PlexPrivilegedPlaybackDescriptor['setup']['selectedPrivateTrackIds'] {
  const videoStreams = part.streams.filter((stream) => stream.streamType === 1);
  const audioStreams = part.streams.filter((stream) => stream.streamType === 2);
  const subtitleStreams = part.streams.filter((stream) => stream.streamType === 3);
  return {
    video: findPrivateTrackId(candidate.video.id, [candidate.video], videoStreams),
    audio: findPrivateTrackId(decision.selectedTrackIds.audio, candidate.audioTracks, audioStreams),
    subtitle: findPrivateTrackId(decision.selectedTrackIds.subtitle, candidate.subtitleTracks, subtitleStreams),
  };
}

function findPrivateTrackId(
  selectedTrackId: PlayerTrackId | null,
  publicTracks: readonly { id: PlayerTrackId }[],
  privateStreams: readonly PlexStream[],
): string | null {
  if (selectedTrackId === null) {
    return null;
  }
  const index = publicTracks.findIndex((track) => track.id === selectedTrackId);
  return privateStreams[index]?.id ?? null;
}

function projectConnection(
  connection: PlexConnection,
): PlexPrivilegedPlaybackDescriptor['selectedConnection'] {
  return {
    protocol: connection.protocol,
    address: connection.address,
    port: connection.port,
    local: connection.local,
    relay: connection.relay,
  };
}

function compactTrackIds(
  selectedTrackIds: DesktopStreamPolicyDecision['selectedTrackIds'],
): readonly PlayerTrackId[] {
  return [selectedTrackIds.video, selectedTrackIds.audio, selectedTrackIds.subtitle].filter(
    (trackId): trackId is PlayerTrackId => trackId !== null,
  );
}

function createPortFailureDiagnostic(
  requestId: PlayerRequestId,
  operation: PlayerRendererSafeDiagnostic['operation'],
): PlayerRendererSafeDiagnostic {
  return {
    component: 'plex-stream-resolver',
    operation,
    status: 'failed',
    reason: 'injected port failed',
    media: { id: requestId, title: 'Plex stream request' },
  };
}

function isUsableConnection(value: PlexConnection | null): value is PlexConnection {
  return (
    value !== null &&
    typeof value.uri === 'string' &&
    value.uri.trim() !== '' &&
    (value.protocol === 'http' || value.protocol === 'https') &&
    typeof value.address === 'string' &&
    value.address.trim() !== '' &&
    Number.isInteger(value.port) &&
    value.port > 0
  );
}

function isUsableAuthHeader(value: PlexStreamResolverAuthHeader | null): value is PlexStreamResolverAuthHeader {
  return (
    value !== null &&
    typeof value.name === 'string' &&
    value.name.trim() !== '' &&
    typeof value.value === 'string' &&
    value.value.trim() !== ''
  );
}
