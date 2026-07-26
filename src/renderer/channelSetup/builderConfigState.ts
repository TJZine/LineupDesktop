import {
  createDefaultChannelSetupConfig,
  normalizeChannelSetupConfig,
} from '../../domain/channelBuilder/config.js';
import type {
  ChannelBuilderStrategyKey,
  ChannelBuilderStrategyScope,
  ChannelSetupConfigContext,
  NormalizedChannelSetupConfig,
} from '../../domain/channelBuilder/types.js';

export type ChannelBuilderConfigState = Readonly<{
  config: NormalizedChannelSetupConfig;
}>;

export type ChannelBuilderConfigMutation =
  | Readonly<{ kind: 'set-build-mode'; value: 'append' | 'merge' | 'replace' }>
  | Readonly<{ kind: 'set-combine-mode'; value: 'separate' | 'combined' }>
  | Readonly<{ kind: 'set-max-channels'; value: number }>
  | Readonly<{ kind: 'set-min-items'; value: number }>
  | Readonly<{ kind: 'toggle-strategy'; strategy: ChannelBuilderStrategyKey }>
  | Readonly<{
      kind: 'set-strategy-priority';
      strategy: ChannelBuilderStrategyKey;
      value: number;
    }>
  | Readonly<{
      kind: 'set-strategy-scope';
      strategy: ChannelBuilderStrategyKey;
      value: ChannelBuilderStrategyScope;
    }>
  | Readonly<{ kind: 'toggle-alternates' }>
  | Readonly<{ kind: 'set-alternate-copies'; value: number }>
  | Readonly<{ kind: 'set-variant-type'; value: 'none' | 'sequential' | 'block' }>
  | Readonly<{ kind: 'set-variant-block-size'; value: number }>
  | Readonly<{
      kind: 'set-series-mode';
      value: 'shuffle' | 'sequential' | 'block';
    }>
  | Readonly<{ kind: 'set-series-block-size'; value: number }>;

export type ChannelBuilderConfigActionId =
  | 'configModeAppend' | 'configModeMerge' | 'configModeReplace'
  | 'configMaxDown' | 'configMaxUp' | 'configMinDown' | 'configMinUp'
  | 'configCombineMode' | 'configAlternates' | 'configAlternateCopies'
  | 'configVariantType' | 'configVariantBlockSize'
  | 'configSeriesMode' | 'configSeriesBlockSize'
  | `${'strategyToggle' | 'strategyPriorityDown' | 'strategyPriorityUp' | 'strategyScope'}:${ChannelBuilderStrategyKey}`;

export function createChannelBuilderConfigState(
  context: ChannelSetupConfigContext,
): Readonly<{ ok: true; state: ChannelBuilderConfigState }> | Readonly<{ ok: false }> {
  const created = createDefaultChannelSetupConfig(context);
  if (!created.ok) return { ok: false };
  return {
    ok: true,
    state: Object.freeze({ config: created.config }),
  };
}

export function recontextualizeChannelBuilderConfigState(
  state: ChannelBuilderConfigState,
  context: ChannelSetupConfigContext,
): Readonly<{ ok: true; state: ChannelBuilderConfigState }> | Readonly<{ ok: false }> {
  return normalizedState({
    ...state.config,
    serverId: context.serverId,
    selectedLibraryIds: [...context.selectedLibraryIds],
  }, context);
}

export function applyChannelBuilderConfigMutation(
  state: ChannelBuilderConfigState,
  mutation: ChannelBuilderConfigMutation,
): Readonly<{ ok: true; state: ChannelBuilderConfigState }> | Readonly<{ ok: false }> {
  const candidate = cloneConfig(state.config);
  switch (mutation.kind) {
    case 'set-build-mode': candidate.buildMode = mutation.value; break;
    case 'set-combine-mode': candidate.actorStudioCombineMode = mutation.value; break;
    case 'set-max-channels': candidate.maxChannels = mutation.value; break;
    case 'set-min-items': candidate.minItemsPerChannel = mutation.value; break;
    case 'toggle-strategy':
      candidate.strategyConfig[mutation.strategy] = {
        ...candidate.strategyConfig[mutation.strategy],
        enabled: !candidate.strategyConfig[mutation.strategy].enabled,
      };
      break;
    case 'set-strategy-priority':
      candidate.strategyConfig[mutation.strategy] = {
        ...candidate.strategyConfig[mutation.strategy],
        priority: mutation.value,
      };
      break;
    case 'set-strategy-scope':
      candidate.strategyConfig[mutation.strategy] = {
        ...candidate.strategyConfig[mutation.strategy],
        scope: mutation.value,
      };
      break;
    case 'toggle-alternates':
      candidate.channelExpansion.addAlternateLineups =
        !candidate.channelExpansion.addAlternateLineups;
      break;
    case 'set-alternate-copies':
      candidate.channelExpansion.alternateLineupCopies = mutation.value;
      break;
    case 'set-variant-type':
      candidate.channelExpansion.variantType = mutation.value;
      break;
    case 'set-variant-block-size':
      candidate.channelExpansion.variantBlockSize = mutation.value;
      break;
    case 'set-series-mode':
      candidate.seriesOrdering.basePlaybackMode = mutation.value;
      break;
    case 'set-series-block-size':
      candidate.seriesOrdering.baseBlockSize = mutation.value;
      break;
  }
  return normalizedState(candidate, {
    serverId: candidate.serverId,
    selectedLibraryIds: candidate.selectedLibraryIds,
  });
}

export function readChannelBuilderConfigRequest(
  state: ChannelBuilderConfigState,
): NormalizedChannelSetupConfig {
  return cloneConfig(state.config);
}

export function applyChannelBuilderConfigAction(
  state: ChannelBuilderConfigState,
  action: ChannelBuilderConfigActionId,
): Readonly<{ ok: true; state: ChannelBuilderConfigState; focusId: string }>
  | Readonly<{ ok: false }> {
  const mutation = readActionMutation(state.config, action);
  if (mutation === null) return { ok: false };
  const updated = applyChannelBuilderConfigMutation(state, mutation);
  return updated.ok
    ? { ...updated, focusId: configActionFocus(action) }
    : updated;
}

function readActionMutation(
  config: NormalizedChannelSetupConfig,
  action: ChannelBuilderConfigActionId,
): ChannelBuilderConfigMutation | null {
  const strategy = action.includes(':')
    ? action.split(':')[1] as ChannelBuilderStrategyKey
    : null;
  if (strategy !== null && Object.hasOwn(config.strategyConfig, strategy)) {
    const strategyConfig = config.strategyConfig[strategy];
    if (action.startsWith('strategyToggle:')) return { kind: 'toggle-strategy', strategy };
    if (!strategyConfig.enabled) return null;
    if (action.startsWith('strategyPriorityDown:')) return { kind: 'set-strategy-priority', strategy, value: Math.max(1, strategyConfig.priority - 1) };
    if (action.startsWith('strategyPriorityUp:')) return { kind: 'set-strategy-priority', strategy, value: Math.min(100, strategyConfig.priority + 1) };
    if (action.startsWith('strategyScope:')) return { kind: 'set-strategy-scope', strategy, value: strategyConfig.scope === 'per-library' ? 'cross-library' : 'per-library' };
  }
  switch (action) {
    case 'configModeAppend': return { kind: 'set-build-mode', value: 'append' };
    case 'configModeMerge': return { kind: 'set-build-mode', value: 'merge' };
    case 'configModeReplace': return { kind: 'set-build-mode', value: 'replace' };
    case 'configMaxDown': return { kind: 'set-max-channels', value: Math.max(1, config.maxChannels - 10) };
    case 'configMaxUp': return { kind: 'set-max-channels', value: Math.min(500, config.maxChannels + 10) };
    case 'configMinDown': return { kind: 'set-min-items', value: Math.max(1, config.minItemsPerChannel - 1) };
    case 'configMinUp': return { kind: 'set-min-items', value: Math.min(500, config.minItemsPerChannel + 1) };
    case 'configCombineMode': return { kind: 'set-combine-mode', value: config.actorStudioCombineMode === 'separate' ? 'combined' : 'separate' };
    case 'configAlternates': return { kind: 'toggle-alternates' };
    case 'configAlternateCopies': return config.channelExpansion.addAlternateLineups
      ? { kind: 'set-alternate-copies', value: config.channelExpansion.alternateLineupCopies === 3 ? 1 : config.channelExpansion.alternateLineupCopies + 1 }
      : null;
    case 'configVariantType': return { kind: 'set-variant-type', value: cycle(config.channelExpansion.variantType, ['none', 'sequential', 'block']) };
    case 'configVariantBlockSize': return config.channelExpansion.variantType === 'block'
      ? { kind: 'set-variant-block-size', value: config.channelExpansion.variantBlockSize === 5 ? 2 : config.channelExpansion.variantBlockSize + 1 }
      : null;
    case 'configSeriesMode': return { kind: 'set-series-mode', value: cycle(config.seriesOrdering.basePlaybackMode, ['shuffle', 'sequential', 'block']) };
    case 'configSeriesBlockSize': return config.seriesOrdering.basePlaybackMode === 'block'
      ? { kind: 'set-series-block-size', value: config.seriesOrdering.baseBlockSize === 5 ? 2 : config.seriesOrdering.baseBlockSize + 1 }
      : null;
    default: return null;
  }
}

function configActionFocus(action: ChannelBuilderConfigActionId): string {
  const [kind, strategy] = action.split(':');
  if (strategy !== undefined) {
    const suffix = kind === 'strategyToggle' ? 'toggle' : kind === 'strategyPriorityDown' ? 'priority-down' : kind === 'strategyPriorityUp' ? 'priority-up' : 'scope';
    return `builder-${strategy}-${suffix}`;
  }
  const focusByAction: Partial<Record<ChannelBuilderConfigActionId, string>> = {
    configModeAppend: 'channel-strategy-build-append', configModeMerge: 'channel-strategy-build-merge',
    configModeReplace: 'channel-strategy-build-replace', configMaxDown: 'builder-max-down',
    configMaxUp: 'builder-max-up', configMinDown: 'builder-min-down',
    configMinUp: 'builder-min-up', configCombineMode: 'builder-combine',
    configAlternates: 'builder-alternates', configAlternateCopies: 'builder-alternate-copies',
    configVariantType: 'builder-variant-type', configVariantBlockSize: 'builder-variant-block',
    configSeriesMode: 'builder-series-mode', configSeriesBlockSize: 'builder-series-block',
  };
  return focusByAction[action] ?? 'setup-next';
}

function cycle<T extends string>(value: T, values: readonly T[]): T {
  return values[(values.indexOf(value) + 1) % values.length] ?? values[0] as T;
}

function normalizedState(
  candidate: NormalizedChannelSetupConfig,
  context: ChannelSetupConfigContext,
): Readonly<{ ok: true; state: ChannelBuilderConfigState }> | Readonly<{ ok: false }> {
  const normalized = normalizeChannelSetupConfig(candidate, context);
  return normalized.ok
    ? { ok: true, state: Object.freeze({ config: normalized.config }) }
    : { ok: false };
}

function cloneConfig(config: NormalizedChannelSetupConfig): {
  -readonly [Key in keyof NormalizedChannelSetupConfig]:
    Key extends 'strategyConfig'
      ? Record<ChannelBuilderStrategyKey, {
          -readonly [Field in keyof NormalizedChannelSetupConfig['strategyConfig'][ChannelBuilderStrategyKey]]:
            NormalizedChannelSetupConfig['strategyConfig'][ChannelBuilderStrategyKey][Field]
        }>
      : Key extends 'channelExpansion'
        ? { -readonly [Field in keyof NormalizedChannelSetupConfig['channelExpansion']]:
            NormalizedChannelSetupConfig['channelExpansion'][Field] }
        : Key extends 'seriesOrdering'
          ? { -readonly [Field in keyof NormalizedChannelSetupConfig['seriesOrdering']]:
              NormalizedChannelSetupConfig['seriesOrdering'][Field] }
          : NormalizedChannelSetupConfig[Key]
} {
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
