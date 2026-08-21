/**
 * Standalone Frame 0 progress server (no full API).
 *
 *   cd apps/api && npm run media:frame0-progress
 *   open http://127.0.0.1:4091/frame0
 */
import express from 'express';
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  handleFrame0Get,
  handleFrame0Login,
  handleFrame0Logout,
  handleFrame0Status,
  handleFrame0Run,
  handlePipelineGet,
  handlePipelineLogin,
  handlePipelineLogout,
  handlePipelineClearLog,
  handlePipelineLogStream,
  handlePipelineRunStream,
} from '../ops/ops-page.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

const port = Number(process.env.FRAME0_PROGRESS_PORT || 4091) || 4091;
const app = express();
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

app.get('/', (_req, res) => res.redirect(302, '/pipeline'));
app.get('/pipeline', (req, res) => {
  void handlePipelineGet(req, res);
});
app.post('/pipeline/login', handlePipelineLogin);
app.get('/pipeline/logout', handlePipelineLogout);
app.post('/pipeline/clear-log', handlePipelineClearLog);
app.post('/pipeline/run-stream', (req, res) => {
  void handlePipelineRunStream(req, res);
});
app.get('/pipeline/log-stream', (req, res) => {
  void handlePipelineLogStream(req, res);
});

app.get('/frame0', (req, res) => {
  void handleFrame0Get(req, res);
});
app.post('/frame0/login', handleFrame0Login);
app.get('/frame0/logout', handleFrame0Logout);
app.get('/frame0/status', (req, res) => {
  void handleFrame0Status(req, res);
});
app.post('/frame0/run', (req, res) => {
  void handleFrame0Run(req, res);
});
app.get('/reports', (_req, res) => res.redirect(302, '/pipeline'));

app.listen(port, '127.0.0.1', () => {
  console.log(`[ops] http://127.0.0.1:${port}/pipeline`);
  console.log(`[ops] Frame 0 tab: http://127.0.0.1:${port}/frame0`);
  console.log(`[ops] password = CONTENT_PIPELINE_PASSWORD / REPORTS_PAGE_PASSWORD (default 54isamr!)`);
});
