import { pool } from '../../db.js';
import { runPipelineNow } from '../../content-pipeline/jobs.js';
import { createConsumer } from '../client.js';
import { kafkaConsumerGroup } from '../config.js';
import { claimProcessedEvent } from '../outbox.js';
import {
  KafkaTopics,
  R2IngestEventTypes,
  type DomainEvent,
  type R2IngestRequestedPayload,
} from '../types.js';

/**
 * Kafka worker: R2IngestRequested → runContentPipeline
 * (discover R2 → owned posts + feed shares + resign → ContentPosted via outbox).
 */
export async function startR2IngestConsumer(): Promise<void> {
  const groupId = `${kafkaConsumerGroup()}-r2-ingest`;
  const consumer = await createConsumer(groupId);
  await consumer.subscribe({ topic: KafkaTopics.R2_INGEST, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) return;
      let event: DomainEvent<R2IngestRequestedPayload>;
      try {
        event = JSON.parse(message.value.toString('utf8')) as DomainEvent<R2IngestRequestedPayload>;
      } catch {
        return;
      }
      if (event.eventType !== R2IngestEventTypes.Requested) return;

      const client = await pool.connect();
      let firstTime = false;
      try {
        firstTime = await claimProcessedEvent(
          client,
          groupId,
          event.eventId,
          event.eventType
        );
      } finally {
        client.release();
      }
      if (!firstTime) return;

      const p = event.payload ?? ({} as R2IngestRequestedPayload);
      console.log(
        `[kafka-r2] R2IngestRequested by=${p.requestedBy ?? '?'} dryRun=${!!p.dryRun}`
      );
      try {
        const stats = await runPipelineNow({
          dryRun: !!p.dryRun,
          resignOnly: !!p.resignOnly,
          ingestOnly: !!p.ingestOnly,
          // Flood by default when payload omits caps.
          maxOriginals: p.maxOriginals,
          maxShares: p.maxShares,
          maxResign: p.maxResign,
          maxMs: p.maxMs ?? 0,
          source: `kafka:${p.requestedBy ?? 'cron'}`,
        });
        console.log(
          `[kafka-r2] done ok=${stats.ok} originals=+${stats.insertedOriginals} shares=+${stats.insertedShares} resigned=${stats.resigned} ms=${stats.ms}`
        );
      } catch (err) {
        console.error('[kafka-r2] pipeline failed', err);
      }
    },
  });

  console.log(`✅ Kafka consumer listening on ${KafkaTopics.R2_INGEST} (group=${groupId})`);
}
