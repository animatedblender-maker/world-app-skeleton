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
} from './frame0-progress.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

const port = Number(process.env.FRAME0_PROGRESS_PORT || 4091) || 4091;
const app = express();
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

app.get('/', (_req, res) => res.redirect(302, '/frame0'));
app.get('/frame0', (req, res) => {
  void handleFrame0Get(req, res);
});
app.post('/frame0/login', handleFrame0Login);
app.get('/frame0/logout', handleFrame0Logout);
app.get('/frame0/status', (req, res) => {
  void handleFrame0Status(req, res);
});
app.get('/pipeline', (_req, res) => res.redirect(302, '/frame0'));
app.get('/reports', (_req, res) => res.redirect(302, '/frame0'));

app.listen(port, '127.0.0.1', () => {
  console.log(`[frame0-progress] http://127.0.0.1:${port}/frame0`);
  console.log(`[frame0-progress] password = CONTENT_PIPELINE_PASSWORD / REPORTS_PAGE_PASSWORD (default 54isamr!)`);
});
