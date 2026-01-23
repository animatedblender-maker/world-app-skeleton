import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { environment } from '../../../envirnoments/envirnoment';

type PushSubscriptionPayload = {
  endpoint: string;
  keys: {
    p256dh: string;
    auth: string;
  };
};

@Injectable({ providedIn: 'root' })
export class PushService {
  private readonly swUrl = '/sw.js';
  private registrationPromise: Promise<ServiceWorkerRegistration> | null = null;

  constructor(private auth: AuthService) {}

  isSupported(): boolean {
    return (
      typeof window !== 'undefined' &&
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      !!environment.pushPublicKey
    );
  }

  async syncIfGranted(): Promise<void> {
    if (!this.isSupported()) return;
    if (!('Notification' in window)) return;
    if (Notification.permission !== 'granted') return;
    await this.ensureSubscription();
  }

  async enableFromUserGesture(): Promise<void> {
    if (!this.isSupported()) return;
    if (!('Notification' in window)) return;

    const permission =
      Notification.permission === 'default'
        ? await Notification.requestPermission()
        : Notification.permission;

    if (permission !== 'granted') return;
    await this.ensureSubscription();
  }

  private async ensureSubscription(): Promise<void> {
    const reg = await this.getRegistration();
    const existing = await reg.pushManager.getSubscription();
    const subscription =
      existing ??
      (await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(environment.pushPublicKey),
      }));

    await this.sendSubscription(subscription);
  }

  private async getRegistration(): Promise<ServiceWorkerRegistration> {
    if (!this.registrationPromise) {
      this.registrationPromise = navigator.serviceWorker.register(this.swUrl);
    }
    return this.registrationPromise;
  }

  private async sendSubscription(subscription: PushSubscription): Promise<void> {
    const token = await this.auth.getAccessToken();
    if (!token) return;

    const payload = subscription.toJSON() as PushSubscriptionPayload;
    if (!payload?.endpoint || !payload?.keys?.p256dh || !payload?.keys?.auth) return;

    const baseUrl = environment.apiBaseUrl || environment.graphqlEndpoint.replace(/\/graphql$/, '');
    await fetch(`${baseUrl}/push/subscribe`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        subscription: payload,
        userAgent: navigator.userAgent,
      }),
    });
  }

  private urlBase64ToUint8Array(base64String: string): ArrayBuffer {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray.buffer;
  }
}
