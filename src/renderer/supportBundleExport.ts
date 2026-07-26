import type { DiagnosticsExportSupportBundleResult } from '../contracts/diagnostics.js';
import {
  applyWorkflowSupportBundleExportStatus,
  type WorkflowState,
} from './workflow.js';

export type SupportBundleExportInvoker = () => Promise<DiagnosticsExportSupportBundleResult>;
export type SupportBundleWorkflowStateProvider = () => WorkflowState;

export class SupportBundleExportCoordinator {
  #activeRequestId: number | null = null;
  #nextRequestId = 0;

  public start(): number | null {
    if (this.#activeRequestId !== null) {
      return null;
    }
    this.#nextRequestId += 1;
    this.#activeRequestId = this.#nextRequestId;
    return this.#activeRequestId;
  }

  public settle(requestId: number): boolean {
    if (this.#activeRequestId !== requestId) {
      return false;
    }
    this.#activeRequestId = null;
    return true;
  }
}

export async function applySupportBundleExportResult(
  readWorkflowState: SupportBundleWorkflowStateProvider,
  exportSupportBundle: SupportBundleExportInvoker,
): Promise<WorkflowState> {
  try {
    const result = await exportSupportBundle();
    return applyWorkflowSupportBundleExportStatus(readWorkflowState(), {
      status: result.status,
      bundleDirectoryName: result.status === 'succeeded' ? result.bundleDirectoryName : null,
      fileCount: result.status === 'succeeded' ? result.fileCount : null,
      redactionStatus: result.redactionReport?.status ?? null,
    });
  } catch {
    return applyWorkflowSupportBundleExportStatus(readWorkflowState(), {
      status: 'failed',
      bundleDirectoryName: null,
      fileCount: null,
      redactionStatus: null,
    });
  }
}
