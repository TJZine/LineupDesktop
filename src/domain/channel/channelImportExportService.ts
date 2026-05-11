import { ChannelImportNormalizer } from './channelImportNormalizer.js';
import type { ChannelConfig, ChannelCreateInput, ImportResult } from './types.js';

type ChannelImportExportServiceConfig = {
  getAllChannels: () => ChannelConfig[];
  isChannelNumberInUse: (number: number) => boolean;
  getNextAvailableNumber: () => number;
  createChannel: (input: ChannelCreateInput) => Promise<ChannelConfig>;
};

export class ChannelImportExportService {
  private readonly normalizer = new ChannelImportNormalizer();
  private readonly getAllChannels: () => ChannelConfig[];
  private readonly isChannelNumberInUse: (number: number) => boolean;
  private readonly getNextAvailableNumber: () => number;
  private readonly createChannel: (input: ChannelCreateInput) => Promise<ChannelConfig>;

  public constructor(config: ChannelImportExportServiceConfig) {
    this.getAllChannels = config.getAllChannels;
    this.isChannelNumberInUse = config.isChannelNumberInUse;
    this.getNextAvailableNumber = config.getNextAvailableNumber;
    this.createChannel = config.createChannel;
  }

  public exportChannels(): string {
    return JSON.stringify(this.getAllChannels(), null, 2);
  }

  public async importChannels(data: string): Promise<ImportResult> {
    const result: ImportResult = {
      success: false,
      importedCount: 0,
      skippedCount: 0,
      errors: [],
    };

    const normalized = this.normalizer.normalizePayload(data);
    if (!normalized.ok) {
      result.errors.push(normalized.error);
      return result;
    }
    result.skippedCount += normalized.skippedCount;

    for (const channelData of normalized.channels) {
      try {
        if (
          typeof channelData.number === 'number' &&
          this.isChannelNumberInUse(channelData.number)
        ) {
          channelData.number = this.getNextAvailableNumber();
        }
        await this.createChannel(channelData);
        result.importedCount++;
      } catch (error) {
        result.skippedCount++;
        result.errors.push(`Failed to import channel: ${this.normalizer.formatErrorMessage(error)}`);
      }
    }

    result.success = result.importedCount > 0;
    return result;
  }
}
