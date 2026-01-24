import { Injectable, NgZone } from '@angular/core';
import { BehaviorSubject, Subject } from 'rxjs';

import { AuthService } from './auth.service';
import { environment } from '../../../envirnoments/envirnoment';

export type CallSignal = {
  type: string;
  conversationId: string;
  from: string;
  callType?: 'audio' | 'video';
  sdp?: any;
  candidate?: any;
};

export type IncomingCall = {
  conversationId: string;
  from: string;
  callType: 'audio' | 'video';
};

@Injectable({ providedIn: 'root' })
export class CallService {
  private ws?: WebSocket;
  private connectedSubject = new BehaviorSubject<boolean>(false);
  readonly connected$ = this.connectedSubject.asObservable();
  private signalSubject = new Subject<CallSignal>();
  readonly signals$ = this.signalSubject.asObservable();
  private incomingSubject = new BehaviorSubject<IncomingCall | null>(null);
  readonly incoming$ = this.incomingSubject.asObservable();
  private destroyed = false;

  constructor(private auth: AuthService, private zone: NgZone) {
    void this.connect();
  }

  get connected(): boolean {
    return this.connectedSubject.value;
  }

  clearIncomingCall(): void {
    this.incomingSubject.next(null);
  }

  sendSignal(type: string, conversationId: string | null, payload?: Record<string, any>): void {
    if (!conversationId || !this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    const msg = {
      type,
      conversationId,
      ...(payload ?? {}),
    };
    try {
      this.ws.send(JSON.stringify(msg));
    } catch {}
  }

  private async connect(): Promise<void> {
    if (this.destroyed) return;
    const token = await this.auth.getAccessToken();
    if (!token) {
      this.connectedSubject.next(false);
      window.setTimeout(() => void this.connect(), 3000);
      return;
    }
    const base = environment.apiBaseUrl || environment.graphqlEndpoint.replace(/\/graphql$/, '');
    const wsBase = base.startsWith('https') ? base.replace(/^https/, 'wss') : base.replace(/^http/, 'ws');
    const wsUrl = `${wsBase}/ws?token=${encodeURIComponent(token)}`;

    if (this.ws && this.ws.url === wsUrl && this.ws.readyState <= WebSocket.OPEN) return;
    this.ws?.close();

    const socket = new WebSocket(wsUrl);
    this.ws = socket;

    socket.onopen = () => {
      this.zone.run(() => this.connectedSubject.next(true));
    };
    socket.onmessage = (event) => {
      this.handleMessage(String(event.data ?? ''));
    };
    socket.onclose = () => {
      this.zone.run(() => this.connectedSubject.next(false));
      this.ws = undefined;
      if (!this.destroyed) {
        window.setTimeout(() => void this.connect(), 3000);
      }
    };
    socket.onerror = () => {
      this.zone.run(() => this.connectedSubject.next(false));
    };
  }

  private handleMessage(raw: string): void {
    let msg: CallSignal | null = null;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    if (!msg) return;
    const type = String(msg?.type ?? '');
    const conversationId = String(msg?.conversationId ?? '');
    const from = String(msg?.from ?? '');
    if (!type || !conversationId || !from) return;

    this.zone.run(() => {
      if (type === 'call-offer') {
        const callType = msg.callType === 'video' ? 'video' : 'audio';
        this.incomingSubject.next({ conversationId, from, callType });
      }

      if (type === 'call-end' || type === 'call-decline' || type === 'call-busy') {
        const pending = this.incomingSubject.value;
        if (pending && pending.conversationId === conversationId) {
          this.incomingSubject.next(null);
        }
      }

      this.signalSubject.next(msg);
    });
  }
}
