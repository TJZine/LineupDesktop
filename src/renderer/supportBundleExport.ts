import type { DiagnosticsExportSupportBundleResult } from '../contracts/diagnostics.js';
import {
  applyWorkflowSupportBundleExportStatus,
  type WorkflowState,
} from './workflow.js';

export type SupportBundleExportInvoker = () => Promise<DiagnosticsExportSupportBundleResult>;
export type SupportBundleWorkflowStateProvider = () => WorkflowState;

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
