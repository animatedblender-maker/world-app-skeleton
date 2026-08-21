/**
 * Legacy entry — Ops UI now lives in `../ops/ops-page.ts`.
 * Re-export so older imports keep working.
 */
export {
  handlePipelineGet,
  handlePipelineLogin,
  handlePipelineLogout,
  handlePipelineRun,
  handlePipelineRunStream,
  handlePipelineClearLog,
  hasPipelineAccess,
  PIPELINE_PAGE_PASSWORD,
} from '../ops/ops-page.js';
