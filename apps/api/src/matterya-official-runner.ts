/**
 * Create / refresh the official Matterya account and optionally send welcome DMs.
 *
 *   npx tsx src/matterya-official-runner.ts --password='…' --welcome=USER_ID
 *   npx tsx src/matterya-official-runner.ts --welcome-email=amr@…
 *   npx tsx src/matterya-official-runner.ts --masquerade-welcome=USER_ID
 *   npx tsx src/matterya-official-runner.ts --masquerade-welcome-email=amr@…
 */
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from './db.js';
import {
  defaultOfficialAvatarPath,
  ensureMatteryaOfficialUser,
  MASQUERADE_WELCOME_MESSAGE,
  sendMatteryaMasqueradeWelcomeMessage,
  sendMatteryaWelcomeMessage,
  WELCOME_MESSAGE,
} from './matterya-official.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env'), override: true });

function argValue(name: string): string | null {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}

async function main() {
  const password = argValue('password') || process.env.MATTERYA_OFFICIAL_PASSWORD || '';
  const avatar = argValue('avatar') || defaultOfficialAvatarPath();
  const id = await ensureMatteryaOfficialUser({ password: password || undefined, avatarPath: avatar });
  const { rows } = await pool.query(
    `select user_id::text, email, username, display_name, avatar_url, is_verified
     from public.profiles where user_id = $1::uuid`,
    [id]
  );
  console.log('[official]', rows[0]);

  const welcomeId = argValue('welcome');
  const welcomeEmail = argValue('welcome-email');
  const masqueradeWelcomeId = argValue('masquerade-welcome');
  const masqueradeWelcomeEmail = argValue('masquerade-welcome-email');
  let target = welcomeId;
  if (!target && welcomeEmail) {
    const hit = await pool.query<{ user_id: string }>(
      `select user_id::text as user_id from public.profiles where lower(email)=lower($1) limit 1`,
      [welcomeEmail]
    );
    target = hit.rows[0]?.user_id ?? null;
  }
  if (target) {
    const result = await sendMatteryaWelcomeMessage(target, WELCOME_MESSAGE);
    console.log('[welcome]', result);
  }

  let masqueradeTarget = masqueradeWelcomeId;
  if (!masqueradeTarget && masqueradeWelcomeEmail) {
    const hit = await pool.query<{ user_id: string }>(
      `select user_id::text as user_id from public.profiles where lower(email)=lower($1) limit 1`,
      [masqueradeWelcomeEmail]
    );
    masqueradeTarget = hit.rows[0]?.user_id ?? null;
  }
  if (masqueradeTarget) {
    const result = await sendMatteryaMasqueradeWelcomeMessage(
      masqueradeTarget,
      MASQUERADE_WELCOME_MESSAGE
    );
    console.log('[masquerade-welcome]', result);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await pool.end().catch(() => undefined);
  });
