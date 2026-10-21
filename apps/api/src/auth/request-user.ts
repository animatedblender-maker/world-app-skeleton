import type { Request } from 'express';
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Same pattern as db.ts — env may load after ESM import hoist from main.ts
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '..', '.env'), override: true });

export type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
  aud?: string | string[];
};

let jwks: JWTVerifyGetKey | null | undefined;

function getJwks(): JWTVerifyGetKey | null {
  if (jwks !== undefined) return jwks;
  const supabaseUrl = process.env.SUPABASE_URL;
  jwks = supabaseUrl
    ? createRemoteJWKSet(new URL(`${supabaseUrl}/auth/v1/.well-known/jwks.json`))
    : null;
  return jwks;
}

export async function getUserFromRequest(req: Request): Promise<AuthedUser | null> {
  try {
    const authHeader = req.headers.authorization ?? '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
    const keys = getJwks();
    if (!token || !keys) return null;
    const { payload } = await jwtVerify(token, keys, {});
    return {
      id: String(payload.sub),
      email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
      role: typeof payload['role'] === 'string' ? payload['role'] : undefined,
      aud:
        typeof payload['aud'] === 'string' || Array.isArray(payload['aud'])
          ? payload['aud']
          : undefined,
    };
  } catch {
    return null;
  }
}

export async function getUserFromToken(token: string | null): Promise<AuthedUser | null> {
  try {
    const keys = getJwks();
    if (!token || !keys) return null;
    const { payload } = await jwtVerify(token, keys, {});
    return {
      id: String(payload.sub),
      email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
      role: typeof payload['role'] === 'string' ? payload['role'] : undefined,
      aud:
        typeof payload['aud'] === 'string' || Array.isArray(payload['aud'])
          ? payload['aud']
          : undefined,
    };
  } catch {
    return null;
  }
}
