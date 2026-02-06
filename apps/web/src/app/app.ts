import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';

import { CallService, IncomingCall } from './core/services/call.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, RouterOutlet],
  template: `
    <router-outlet />
    <div class="global-call" *ngIf="incomingCall && !isMessagesRoute">
      <div class="global-call-card">
        <div class="global-call-title">
          Incoming {{ incomingCall.callType === 'video' ? 'video' : 'voice' }} call
        </div>
        <div class="global-call-actions">
          <button type="button" class="global-call-btn accept" (click)="acceptCall()">Accept</button>
          <button type="button" class="global-call-btn decline" (click)="declineCall()">Decline</button>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
    .global-call{
      position:fixed;
      inset:0;
      display:grid;
      place-items:center;
      background:rgba(5,10,18,0.55);
      backdrop-filter:blur(8px);
      z-index:140;
      padding:16px;
    }
    .global-call-card{
      width:min(92vw, 420px);
      background:rgba(8,16,28,0.96);
      color:#eef6ff;
      border-radius:22px;
      padding:18px;
      box-shadow:0 20px 50px rgba(0,0,0,0.35);
      display:flex;
      flex-direction:column;
      gap:14px;
      align-items:center;
      text-align:center;
    }
    .global-call-title{
      font-size:16px;
      font-weight:700;
    }
    .global-call-actions{
      display:flex;
      gap:12px;
      justify-content:center;
      flex-wrap:wrap;
    }
    .global-call-btn{
      border:0;
      border-radius:16px;
      padding:10px 16px;
      font-weight:600;
      cursor:pointer;
    }
    .global-call-btn.accept{
      background:#2f9d66;
      color:#fff;
    }
    .global-call-btn.decline{
      background:#d84c4c;
      color:#fff;
    }
    `
  ],
})
export class AppComponent {
  incomingCall: IncomingCall | null = null;
  isMessagesRoute = false;

  constructor(private callService: CallService, private router: Router) {
    this.callService.incoming$.subscribe((call) => {
      this.incomingCall = call;
    });
    this.isMessagesRoute = this.router.url.startsWith('/messages');
    this.router.events.pipe(filter((event) => event instanceof NavigationEnd)).subscribe(() => {
      this.isMessagesRoute = this.router.url.startsWith('/messages');
    });
  }

  acceptCall(): void {
    if (!this.incomingCall) return;
    const { conversationId, callType, from } = this.incomingCall;
    this.callService.clearIncomingCall();
    void this.router.navigate(['/messages'], {
      queryParams: { c: conversationId, call: callType, from },
    });
  }

  declineCall(): void {
    if (!this.incomingCall) return;
    const { conversationId, callId } = this.incomingCall;
    this.callService.sendSignal('call-decline', conversationId, { callId });
    this.callService.clearIncomingCall();
  }
}
