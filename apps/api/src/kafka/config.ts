/** Kafka / Redpanda runtime config (env-driven). */

function flag(name: string): boolean {
  const raw = (process.env[name] ?? '').trim().toLowerCase();
  return raw === '1' || raw === 'true' || raw === 'yes';
}

export function kafkaEnabled(): boolean {
  return flag('KAFKA_ENABLED');
}

/**
 * When Kafka is on, still run legacy inline side-effects (e.g. notify in sendMessage).
 * Use for shadow traffic before cutting over.
 */
export function kafkaShadowMode(): boolean {
  return flag('KAFKA_SHADOW');
}

export function kafkaBrokers(): string[] {
  const raw = process.env.KAFKA_BROKERS ?? 'localhost:19092';
  return raw
    .split(',')
    .map((b) => b.trim())
    .filter(Boolean);
}

export function kafkaClientId(): string {
  return process.env.KAFKA_CLIENT_ID ?? 'matterya-api';
}

export function kafkaConsumerGroup(): string {
  return process.env.KAFKA_CONSUMER_GROUP ?? 'matterya-api-workers';
}

export function kafkaPublisherIntervalMs(): number {
  const n = Number(process.env.KAFKA_PUBLISHER_INTERVAL_MS ?? 500);
  if (!Number.isFinite(n) || n <= 0) return 500;
  return Math.max(200, Math.min(60_000, n));
}

export function kafkaPublisherBatchSize(): number {
  const n = Number(process.env.KAFKA_PUBLISHER_BATCH_SIZE ?? 50);
  if (!Number.isFinite(n) || n <= 0) return 50;
  return Math.max(1, Math.min(200, n));
}

/** TLS for managed Kafka (Upstash, Confluent, Aiven, Redpanda Cloud). */
export function kafkaSsl(): boolean {
  if (flag('KAFKA_SSL')) return true;
  // Heuristic: non-local brokers almost always need TLS.
  const brokers = kafkaBrokers();
  return brokers.some((b) => !b.includes('localhost') && !b.startsWith('127.'));
}

export type KafkaSaslConfig = {
  mechanism: 'plain' | 'scram-sha-256' | 'scram-sha-512';
  username: string;
  password: string;
};

export function kafkaSasl(): KafkaSaslConfig | null {
  const username = (process.env.KAFKA_SASL_USERNAME ?? process.env.KAFKA_USERNAME ?? '').trim();
  const password = (process.env.KAFKA_SASL_PASSWORD ?? process.env.KAFKA_PASSWORD ?? '').trim();
  if (!username || !password) return null;

  // Confluent Cloud uses SASL/PLAIN; Upstash typically SCRAM-SHA-256.
  const brokers = kafkaBrokers().join(',');
  const defaultMech: KafkaSaslConfig['mechanism'] = brokers.includes('confluent.cloud')
    ? 'plain'
    : 'scram-sha-256';
  const raw = (process.env.KAFKA_SASL_MECHANISM ?? defaultMech).trim().toLowerCase();
  let mechanism: KafkaSaslConfig['mechanism'] = defaultMech;
  if (raw === 'plain') mechanism = 'plain';
  if (raw === 'scram-sha-512' || raw === 'scram_sha_512') mechanism = 'scram-sha-512';
  if (raw === 'scram-sha-256' || raw === 'scram_sha_256') mechanism = 'scram-sha-256';

  return { mechanism, username, password };
}

/** Topic replication for ensureTopics (local Redpanda = 1, many clouds = 3). */
export function kafkaReplicationFactor(): number {
  const n = Number(process.env.KAFKA_REPLICATION_FACTOR ?? (kafkaSsl() ? 3 : 1));
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.min(5, Math.floor(n));
}
