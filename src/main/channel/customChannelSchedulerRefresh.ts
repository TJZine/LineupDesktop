import type { CustomChannelOperation } from '../../contracts/customChannels.js';

export type CustomChannelRefreshReason =
  | 'save'
  | 'delete'
  | 'reorder'
  | 'visibility';

export interface CustomChannelSchedulerRefreshEvent {
  operation: CustomChannelOperation;
  reason: CustomChannelRefreshReason;
  changedChannelId: string | null;
}

export type CustomChannelSchedulerRefreshHook = (
  event: CustomChannelSchedulerRefreshEvent,
) => void | Promise<void>;
