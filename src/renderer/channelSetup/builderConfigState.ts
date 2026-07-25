import { createDefaultChannelSetupConfig } from '../../domain/channelBuilder/config.js';
import type { NormalizedChannelSetupConfig } from '../../domain/channelBuilder/types.js';

export type ChannelBuilderConfigState = Readonly<{
  config: NormalizedChannelSetupConfig;
}>;

export function createChannelBuilderConfigState(
  context: Readonly<{ serverId: string; selectedLibraryIds: readonly string[] }>,
): Readonly<{ ok: true; state: ChannelBuilderConfigState }> | Readonly<{ ok: false }> {
  const created = createDefaultChannelSetupConfig(context);
  if (!created.ok) return { ok: false };
  return {
    ok: true,
    state: Object.freeze({ config: created.config }),
  };
}

export function readChannelBuilderConfigRequest(
  state: ChannelBuilderConfigState,
): NormalizedChannelSetupConfig {
  return cloneConfig(state.config);
}

function cloneConfig(config: NormalizedChannelSetupConfig): NormalizedChannelSetupConfig {
  return {
    ...config,
    selectedLibraryIds: [...config.selectedLibraryIds],
    strategyConfig: Object.fromEntries(
      Object.entries(config.strategyConfig).map(([key, value]) => [
        key,
        { ...value },
      ]),
    ) as NormalizedChannelSetupConfig['strategyConfig'],
    channelExpansion: { ...config.channelExpansion },
    seriesOrdering: { ...config.seriesOrdering },
  };
}
