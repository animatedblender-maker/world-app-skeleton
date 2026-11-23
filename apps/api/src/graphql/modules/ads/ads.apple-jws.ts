import { X509Certificate } from 'node:crypto';

import { compactVerify, importX509 } from 'jose';

/** Must match StoreKit product + `AD_CAMPAIGN_CREATE_PRODUCT_ID` in ads.billing.ts */
const EXPECTED_PRODUCT_ID = 'com.matterya.worldapp.ads.campaign_create';

/** Apple Root CA - G3 (https://www.apple.com/certificateauthority/) */
const APPLE_ROOT_CA_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

const EXPECTED_BUNDLE_ID = 'com.matterya.worldapp';

export type VerifiedStoreKitTransaction = {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  environment: string;
};

function b64urlToBuf(segment: string): Buffer {
  const b64 = segment.replace(/-/g, '+').replace(/_/g, '/');
  const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4));
  return Buffer.from(b64 + pad, 'base64');
}

function derToPem(derB64: string): string {
  const body = derB64.replace(/\s+/g, '');
  const lines = body.match(/.{1,64}/g) ?? [body];
  return `-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----`;
}

function assertAppleCertChain(x5c: string[]): void {
  if (!Array.isArray(x5c) || x5c.length < 1) {
    throw new Error('Purchase JWS missing certificate chain.');
  }
  const certs = x5c.map((der) => new X509Certificate(derToPem(der)));
  const now = new Date();
  for (const cert of certs) {
    if (new Date(cert.validFrom) > now || new Date(cert.validTo) < now) {
      throw new Error('Purchase certificate expired or not yet valid.');
    }
  }

  // Each cert must be signed by the next in the chain (leaf → … → root-or-intermediate).
  for (let i = 0; i < certs.length - 1; i++) {
    const child = certs[i]!;
    const issuer = certs[i + 1]!;
    if (!child.verify(issuer.publicKey)) {
      throw new Error('Purchase certificate chain is invalid.');
    }
  }

  const root = new X509Certificate(APPLE_ROOT_CA_G3_PEM);
  const chainRoot = certs[certs.length - 1]!;
  // Last entry is either Apple Root CA G3 itself, or an intermediate signed by it.
  if (chainRoot.fingerprint256 === root.fingerprint256) {
    return;
  }
  if (!chainRoot.verify(root.publicKey)) {
    throw new Error('Purchase certificate is not rooted at Apple Root CA G3.');
  }
}

/**
 * Cryptographically verify a StoreKit 2 transaction JWS (x5c → Apple Root CA G3).
 * Never trust base64-decoded payload alone.
 */
export async function verifyStoreKitTransactionJws(
  jws: string
): Promise<VerifiedStoreKitTransaction> {
  const raw = String(jws ?? '').trim();
  const parts = raw.split('.');
  if (parts.length !== 3) {
    throw new Error('Purchase JWS is malformed.');
  }

  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(b64urlToBuf(parts[0]!).toString('utf8')) as {
      alg?: string;
      x5c?: string[];
    };
  } catch {
    throw new Error('Purchase JWS header is invalid.');
  }

  const x5c = header.x5c;
  assertAppleCertChain(x5c ?? []);

  const leafPem = derToPem(x5c![0]!);
  const key = await importX509(leafPem, header.alg ?? 'ES256');
  let payloadBytes: Uint8Array;
  try {
    const verified = await compactVerify(raw, key);
    payloadBytes = verified.payload;
  } catch {
    throw new Error('Purchase JWS signature verification failed.');
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(Buffer.from(payloadBytes).toString('utf8')) as Record<
      string,
      unknown
    >;
  } catch {
    throw new Error('Purchase JWS payload is invalid.');
  }

  const productId = String(payload.productId ?? '').trim();
  const bundleId = String(payload.bundleId ?? '').trim();
  const transactionId = String(payload.transactionId ?? '').trim();
  const originalTransactionId = String(
    payload.originalTransactionId ?? payload.transactionId ?? ''
  ).trim();
  const environment = String(payload.environment ?? '').trim();

  if (!transactionId) {
    throw new Error('Purchase transaction id missing.');
  }
  if (productId !== EXPECTED_PRODUCT_ID) {
    throw new Error('Purchase product mismatch.');
  }
  if (bundleId !== EXPECTED_BUNDLE_ID) {
    throw new Error('Purchase bundle mismatch.');
  }
  if (environment && !['Sandbox', 'Production', 'Xcode'].includes(environment)) {
    throw new Error('Purchase environment is not recognized.');
  }

  return {
    transactionId,
    originalTransactionId: originalTransactionId || transactionId,
    productId,
    bundleId,
    environment: environment || 'unknown',
  };
}
