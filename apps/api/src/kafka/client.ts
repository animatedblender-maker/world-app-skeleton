import {
  Kafka,
  logLevel,
  Partitioners,
  type Admin,
  type Consumer,
  type KafkaConfig,
  type Producer,
  type SASLOptions,
} from 'kafkajs';
import {
  kafkaBrokers,
  kafkaClientId,
  kafkaReplicationFactor,
  kafkaSasl,
  kafkaSsl,
} from './config.js';
import { KafkaTopics } from './types.js';

let kafka: Kafka | null = null;
let producer: Producer | null = null;
let admin: Admin | null = null;

function buildKafkaConfig(): KafkaConfig {
  const config: KafkaConfig = {
    clientId: kafkaClientId(),
    brokers: kafkaBrokers(),
    logLevel: logLevel.WARN,
    // Silence v2 partitioner migration noise in prod logs
    retry: {
      initialRetryTime: 300,
      retries: 8,
    },
    connectionTimeout: 10_000,
    requestTimeout: 30_000,
  };

  if (kafkaSsl()) {
    config.ssl = true;
  }

  const sasl = kafkaSasl();
  if (sasl) {
    config.sasl = {
      mechanism: sasl.mechanism,
      username: sasl.username,
      password: sasl.password,
    } as SASLOptions;
  }

  return config;
}

export function getKafka(): Kafka {
  if (!kafka) {
    kafka = new Kafka(buildKafkaConfig());
  }
  return kafka;
}

export async function getProducer(): Promise<Producer> {
  if (!producer) {
    producer = getKafka().producer({
      allowAutoTopicCreation: true,
      // Managed clouds often don't need strict idempotent producer; keep simple & stable.
      idempotent: false,
      createPartitioner: Partitioners.DefaultPartitioner,
    });
    await producer.connect();
  }
  return producer;
}

export async function createConsumer(groupId: string): Promise<Consumer> {
  const consumer = getKafka().consumer({
    groupId,
    allowAutoTopicCreation: true,
    sessionTimeout: 30_000,
  });
  await consumer.connect();
  return consumer;
}

export async function ensureTopics(): Promise<void> {
  if (!admin) {
    admin = getKafka().admin();
    await admin.connect();
  }
  try {
    const existing = await admin.listTopics();
    const wanted = Object.values(KafkaTopics);
    const missing = wanted.filter((t) => !existing.includes(t));
    if (!missing.length) return;

    const rf = kafkaReplicationFactor();
    await admin.createTopics({
      waitForLeaders: true,
      topics: missing.map((topic) => ({
        topic,
        numPartitions: topic === KafkaTopics.MESSAGES ? 6 : 3,
        replicationFactor: rf,
      })),
    });
    console.log(`✅ Kafka topics ready: ${missing.join(', ')} (RF=${rf})`);
  } catch (err) {
    // Many managed clusters block createTopics — create in console instead.
    const msg = err instanceof Error ? err.message : String(err);
    console.warn(
      `⚠️ Could not auto-create Kafka topics (${msg}). ` +
        'Create them in your Kafka provider UI if produce/consume fails: ' +
        Object.values(KafkaTopics).join(', ')
    );
  }
}

export async function disconnectKafka(): Promise<void> {
  try {
    await producer?.disconnect();
  } catch {
    /* ignore */
  }
  try {
    await admin?.disconnect();
  } catch {
    /* ignore */
  }
  producer = null;
  admin = null;
  kafka = null;
}
