import {
  discoverChannelBuilderFacets,
  ensureChannelBuilderFacetDiscoveryNotAborted,
  isValidChannelBuilderFacetDiscoveryInput,
  selectChannelBuilderFacetLibraries,
  type ChannelBuilderFacetDiscoveryInput,
  type ChannelBuilderFacetDiscoveryResult,
  type ChannelBuilderFacetSource,
} from './channelBuilderFacetDiscovery.js';
import {
  ChannelBuilderFacetTransportUnavailableError,
  type ChannelBuilderFacetAccessPort,
} from './channelBuilderFacetSession.js';
import {
  createChannelBuilderFacetMaterializationIndex,
  type ChannelBuilderFacetMaterializationIndex,
} from './channelBuilderFacetMaterialization.js';
import { LivePlexTransportError } from './livePlexTransport.js';

export class DesktopPlexChannelBuilderFacetSource implements ChannelBuilderFacetSource {
  readonly #accessPort: ChannelBuilderFacetAccessPort;

  constructor(accessPort: ChannelBuilderFacetAccessPort) {
    this.#accessPort = accessPort;
  }

  async discover(input: ChannelBuilderFacetDiscoveryInput): Promise<ChannelBuilderFacetDiscoveryResult> {
    if (
      !isValidChannelBuilderFacetDiscoveryInput(input) ||
      input.signal.aborted
    ) {
      return { kind: 'canceled', snapshot: null, materializationIndex: null };
    }
    const owned = { index: null as ChannelBuilderFacetMaterializationIndex | null };
    try {
      const result = await this.#accessPort.withSession(
        {
          expectedContext: input.context,
          selectedLibraryIds: input.normalizedConfig.selectedLibraryIds,
          deadlineAtMs: input.deadlineAtMs,
          signal: input.signal,
        },
        async (session) => {
          ensureChannelBuilderFacetDiscoveryNotAborted(input);
          const selectedLibraries = selectChannelBuilderFacetLibraries(session.libraries, input.normalizedConfig);
          const discovered = await discoverChannelBuilderFacets(input, session, selectedLibraries);
          owned.index = createChannelBuilderFacetMaterializationIndex(input.context, discovered.indexEntries);
          return {
            snapshot: discovered.snapshot,
            materializationIndex: owned.index,
          };
        },
      );
      ensureChannelBuilderFacetDiscoveryNotAborted(input);
      return {
        kind: result.snapshot.aggregate.status,
        snapshot: result.snapshot,
        materializationIndex: result.materializationIndex,
      };
    } catch (error) {
      owned.index?.dispose();
      if (input.signal.aborted) {
        return { kind: 'canceled', snapshot: null, materializationIndex: null };
      }
      if (
        error instanceof LivePlexTransportError &&
        (error.code === 'auth-required' || error.code === 'auth-invalid')
      ) {
        return failed('CHANNEL_PLEX_REQUIRED', false);
      }
      if (hasSafeCode(error, 'CHANNEL_PLEX_REQUIRED')) {
        return failed('CHANNEL_PLEX_REQUIRED', false);
      }
      if (hasSafeCode(error, 'CHANNEL_CONTEXT_CHANGED')) {
        return failed('CHANNEL_CONTEXT_CHANGED', true);
      }
      return failed('CHANNEL_UNKNOWN', error instanceof ChannelBuilderFacetTransportUnavailableError ? false : true);
    }
  }
}


function failed(
  code: 'CHANNEL_PLEX_REQUIRED' | 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_UNKNOWN',
  retryable: boolean,
): ChannelBuilderFacetDiscoveryResult {
  return {
    kind: 'failed',
    snapshot: null,
    materializationIndex: null,
    error: { code, retryable },
  };
}

function hasSafeCode(error: unknown, code: string): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    Object.getOwnPropertyDescriptor(error, 'code')?.value === code
  );
}
