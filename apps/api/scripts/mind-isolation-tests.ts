/**
 * MIND-023 deepen: CI-friendly Public ↔ Masquerade isolation checks.
 *
 *   cd apps/api && npx tsx scripts/mind-isolation-tests.ts
 *
 * Loads apps/api/.env. Exits 1 only when overall status is fail
 * (pass/warn are OK for CI). Prints JSON report.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envPath = path.join(root, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!m) continue;
    if (!process.env[m[1]!]) {
      process.env[m[1]!] = m[2]!.replace(/^["']|["']$/g, '');
    }
  }
}

const { pool } = await import('../src/db.js');
const {
  assertSurfaceNamespace,
  runMasqueradeIsolationChecks,
  isolationOverall,
} = await import('../src/recommendation/mind-isolation.js');

function assertNamespaceBehavior(): { id: string; status: 'pass' | 'fail'; detail: string } {
  try {
    assertSurfaceNamespace('home_for_you', 'public');
    assertSurfaceNamespace('hubs_for_you', 'public');
    assertSurfaceNamespace('masquerade_for_you', 'masquerade');
    let threwPublic = false;
    let threwMasq = false;
    try {
      assertSurfaceNamespace('masquerade_for_you', 'public');
    } catch {
      threwPublic = true;
    }
    try {
      assertSurfaceNamespace('home_for_you', 'masquerade');
    } catch {
      threwMasq = true;
    }
    if (!threwPublic || !threwMasq) {
      return {
        id: 'assert_surface_namespace',
        status: 'fail',
        detail: 'expected cross-namespace asserts to throw',
      };
    }
    return {
      id: 'assert_surface_namespace',
      status: 'pass',
      detail: 'namespace guards throw on Public↔Masquerade mismatch',
    };
  } catch (err: any) {
    return {
      id: 'assert_surface_namespace',
      status: 'fail',
      detail: err?.message ?? String(err),
    };
  }
}

async function main() {
  const unit = assertNamespaceBehavior();
  const checks = await runMasqueradeIsolationChecks();
  const all = [
    {
      id: unit.id,
      label: 'assertSurfaceNamespace unit',
      status: unit.status,
      detail: unit.detail,
    },
    ...checks,
  ];
  const overall = isolationOverall(all);
  const report = {
    ok: overall !== 'fail',
    harness: 'mind-isolation-tests',
    handbook: 'MIND-023 / §6',
    overall,
    checks: all,
  };
  console.log(JSON.stringify(report, null, 2));
  await pool.end();
  if (overall === 'fail') process.exit(1);
}

main().catch(async (err) => {
  console.error(err);
  try {
    await pool.end();
  } catch {
    /* ignore */
  }
  process.exit(1);
});
