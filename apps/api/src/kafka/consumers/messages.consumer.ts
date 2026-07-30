import { pool } from '../../db.js';
import { NotificationsService } from '../../graphql/modules/notifications/notifications.service.js';
import { createConsumer } from '../client.js';
import { kafkaConsumerGroup } from '../config.js';
import { claimProcessedEvent } from '../outbox.js';
import {
  KafkaTopics,
  MessageEventTypes,
  type DomainEvent,
  type MessageSentPayload,
} from '../types.js';

const notifications = new NotificationsService();

/**
 * Handles matterya.messages:
 *  - MessageSent → push + in-app notification for recipients
 *  (Edit/Delete reserved for future projectors)
 */
export async function startMessagesConsumer(): Promise<void> {
  const groupId = kafkaConsumerGroup();
  const consumer = await createConsumer(groupId);
  await consumer.subscribe({ topic: KafkaTopics.MESSAGES, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) return;
      let event: DomainEvent;
      try {
        event = JSON.parse(message.value.toString('utf8')) as DomainEvent;
      } catch {
        console.warn('[kafka-messages] bad JSON payload');
        return;
      }

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

      try {
        await handleEvent(event);
      } catch (err) {
        // Release claim so a later redelivery can retry.
        try {
          await pool.query(
            `delete from public.kafka_processed_events where consumer_group = $1 and event_id = $2`,
            [groupId, event.eventId]
          );
        } catch {
          /* ignore */
        }
        console.warn(`[kafka-messages] handler failed ${event.eventType} ${event.eventId}`, err);
      }
    },
  });

  console.log(`✅ Kafka consumer listening on ${KafkaTopics.MESSAGES} (group=${groupId})`);
}

async function handleEvent(event: DomainEvent): Promise<void> {
  switch (event.eventType) {
    case MessageEventTypes.Sent:
      await handleMessageSent(event as DomainEvent<MessageSentPayload>);
      break;
    case MessageEventTypes.Edited:
    case MessageEventTypes.Deleted:
      // Future: fan-out realtime / search projectors.
      break;
    default:
      break;
  }
}

async function handleMessageSent(event: DomainEvent<MessageSentPayload>): Promise<void> {
  const p = event.payload;
  if (!p?.conversationId || !p?.senderId) return;
  if (p.isCallLog || p.isReaction) return;

  const recipients = Array.isArray(p.recipientIds) ? p.recipientIds : [];
  for (const targetId of recipients) {
    if (!targetId || targetId === p.senderId) continue;
    try {
      await notifications.notifyMessage(targetId, p.senderId, p.conversationId, {
        senderName: p.senderName,
        preview: p.preview,
      });
    } catch (err) {
      console.warn(`[kafka-messages] notify failed → ${targetId}`, err);
    }
  }
}
