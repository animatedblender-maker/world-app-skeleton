import express from 'express';
import cors from 'cors';
import { createYoga, createSchema } from 'graphql-yoga';
import { jwtVerify, createRemoteJWKSet } from 'jose';
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
// ----------------------------------------------------
// ✅ Force-load apps/api/.env (even if run from repo root)
// ----------------------------------------------------
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// src/main.ts  -> apps/api/src
// we want       -> apps/api/.env
dotenv.config({ path: path.join(__dirname, '..', '.env') });
// ✅ ts-node --esm on Windows needs explicit ".ts"
import { typeDefs } from './graphql/typeDefs.ts';
import { resolvers } from './graphql/resolvers.ts';
const ORIGIN = process.env.WEB_ORIGIN ?? 'http://localhost:4200';
const PORT = Number(process.env.PORT ?? 3000);
const SUPABASE_URL = process.env.SUPABASE_URL;
if (!SUPABASE_URL) {
    console.warn('⚠️ SUPABASE_URL not set. JWT verification will fail until you set it.');
}
else {
    console.log('✅ SUPABASE_URL loaded: YES');
}
if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    console.warn('⚠️ SUPABASE_SERVICE_ROLE_KEY missing (apps/api/.env not loaded or key missing)');
}
else {
    console.log('✅ SUPABASE_SERVICE_ROLE_KEY loaded: YES');
}
const JWKS = SUPABASE_URL
    ? createRemoteJWKSet(new URL(`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`))
    : null;
async function getUserFromRequest(req) {
    try {
        const authHeader = req.headers.authorization ?? '';
        const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
        if (!token || !JWKS)
            return null;
        const { payload } = await jwtVerify(token, JWKS, {});
        return {
            id: String(payload.sub),
            email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
            role: typeof payload['role'] === 'string' ? payload['role'] : undefined,
            aud: typeof payload['aud'] === 'string' || Array.isArray(payload['aud'])
                ? payload['aud']
                : undefined,
        };
    }
    catch {
        return null;
    }
}
const yoga = createYoga({
    schema: createSchema({ typeDefs, resolvers }),
    graphqlEndpoint: '/graphql',
    context: async ({ req }) => ({
        req,
        user: await getUserFromRequest(req),
    }),
});
const app = express();
app.use(cors({
    origin: ORIGIN,
    credentials: true,
}));
// ✅ health endpoint (typed _req to avoid implicit any)
app.get('/health', (_req, res) => res.json({ ok: true }));
app.use('/graphql', yoga);
app.listen(PORT, () => {
    console.log(`✅ GraphQL running at http://localhost:${PORT}/graphql`);
    console.log(`✅ Health at        http://localhost:${PORT}/health`);
    console.log(`✅ CORS origin allowed: ${ORIGIN}`);
});
