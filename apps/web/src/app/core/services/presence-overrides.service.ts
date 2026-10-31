import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

export type PresenceOverride = {
  total?: number | null;
  online?: number | null;
};

export type PresenceOverridesMap = Record<string, PresenceOverride>;

const STORAGE_KEY = 'worldapp.presenceOverrides.v1';

@Injectable({ providedIn: 'root' })
export class PresenceOverridesService {
  private overrides$ = new BehaviorSubject<PresenceOverridesMap>(this.load());

  getOverrides(): PresenceOverridesMap {
    return this.overrides$.value;
  }

  observe() {
    return this.overrides$.asObservable();
  }

  setOverride(code: string, override: PresenceOverride | null): void {
    const key = String(code ?? '').trim().toUpperCase();
    if (!key) return;

    const next = { ...this.overrides$.value };
    const normalized = this.normalizeOverride(override);

    if (!normalized) {
      delete next[key];
    } else {
      next[key] = normalized;
    }

    this.overrides$.next(next);
    this.save(next);
  }

  clearAll(): void {
    this.overrides$.next({});
    this.save({});
  }

  private normalizeCount(value: any): number | null {
    if (value === null || value === undefined || value === '') return null;
    const n = Number(value);
    if (!Number.isFinite(n)) return null;
    return Math.max(0, Math.floor(n));
  }

  private normalizeOverride(override: PresenceOverride | null): PresenceOverride | null {
    if (!override) return null;
    const total = this.normalizeCount(override.total);
    let online = this.normalizeCount(override.online);

    if (total !== null && online !== null && online > total) {
      online = total;
    }

    if (total === null && online === null) return null;
    return { total, online };
  }

  private load(): PresenceOverridesMap {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return {};
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') return {};
      const out: PresenceOverridesMap = {};
      for (const [code, override] of Object.entries(parsed)) {
        const normalized = this.normalizeOverride(override as PresenceOverride);
        if (normalized) out[String(code).toUpperCase()] = normalized;
      }
      return out;
    } catch {
      return {};
    }
  }

  private save(map: PresenceOverridesMap): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
    } catch {}
  }
}
