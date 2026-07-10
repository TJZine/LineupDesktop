import type { CustomChannelErrorCode, CustomChannelOperation } from '../../contracts/customChannels.js';
import type { ChannelLogger } from '../../domain/channel/index.js';

export interface CustomChannelDiagnosticRecord {
  operation: CustomChannelOperation;
  status: 'succeeded' | 'failed';
  channelCount?: number;
  changedChannelId?: string | null;
  errorCode?: CustomChannelErrorCode;
}

export function recordCustomChannelDiagnostic(
  logger: Pick<ChannelLogger, 'warn'> | undefined,
  record: CustomChannelDiagnosticRecord,
): void {
  if (record.status === 'failed') {
    logger?.warn('Custom channel operation failed.', sanitizeDiagnosticRecord(record));
  }
}

function sanitizeDiagnosticRecord(
  record: CustomChannelDiagnosticRecord,
): Record<string, string | number | null> {
  const safe: Record<string, string | number | null> = {
    operation: record.operation,
    status: record.status,
  };
  if (record.channelCount !== undefined) safe.channelCount = record.channelCount;
  if (record.changedChannelId !== undefined) safe.changedChannelId = record.changedChannelId;
  if (record.errorCode !== undefined) safe.errorCode = record.errorCode;
  return safe;
}
