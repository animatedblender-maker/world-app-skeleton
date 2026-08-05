import { Injectable } from '@angular/core';
import type { CountryModel } from '../data/countries.service';
import { environment } from '../../envirnoments/envirnoment';

type CountriesPayload = { features: any[]; countries: CountryModel[] };

export type ConnectionPoint = {
  id: string | number;
  lat: number;
  lng: number;
  cc?: string | null;
  color?: string;
  radius?: number;
};

/**
 * True 3D Google globe (maps3d Map3DElement) — photorealistic Earth sphere.
 * Falls back to vector 2D Map only if maps3d is unavailable.
 *
 * iOS uses MapKit hybrid globe; web uses Google Map3D HYBRID (satellite 3D).
 */
@Injectable({ providedIn: 'root' })
export class GlobeService {
  private map3d: any = null;
  private map2d: any = null;
  private google: any = null;
  private maps3dLib: any = null;
  private hostEl: HTMLElement | null = null;
  private mode: '3d' | '2d' | null = null;

  private readyResolver: (() => void) | null = null;
  private readyPromise = new Promise<void>((resolve) => {
    this.readyResolver = resolve;
  });
  private readySettled = false;

  private countries: CountryModel[] = [];
  private features: any[] = [];
  private cachedPayload: CountriesPayload | null = null;
  private countryClickCb: ((country: CountryModel) => void) | null = null;
  private selectedId: number | null = null;

  private cachedConnections: ConnectionPoint[] = [];
  private onlineConnectionIds = new Set<string>();
  private markers3d = new Map<string, any>();
  private markers2d = new Map<string, any>();
  private selectedPolygon2d: any = null;
  private renderingPaused = false;
  private interactive = true;
  private gestureHost: HTMLElement | null = null;
  private unbindGestures: (() => void) | null = null;
  private touchMode: 'none' | 'orbit' | 'pinch' = 'none';
  private lastTouchX = 0;
  private lastTouchY = 0;
  private lastPinchDist = 0;
  private gestureCenterLat = 20;
  private gestureCenterLng = 10;
  private gestureRange = 42_000_000;
  private gestureHeading = 0;
  private gestureTilt = 0;

  /** iOS AppleMapGlobeView globeDistance */
  private readonly GLOBE_RANGE_M = 42_000_000;
  private readonly FOCUS_RANGE_M = 2_800_000;

  init(globeEl: HTMLElement): void {
    this.teardown();
    this.hostEl = globeEl;
    if (getComputedStyle(globeEl).position === 'static') {
      globeEl.style.position = 'relative';
    }
    globeEl.style.background = '#000810';
    globeEl.style.overflow = 'hidden';

    void this.bootstrap(globeEl);
    window.addEventListener('resize', () => this.resize());
  }

  private teardown(): void {
    try {
      this.unbindGestures?.();
    } catch {}
    this.unbindGestures = null;
    this.gestureHost = null;
    try {
      this.map3d?.remove?.();
    } catch {}
    this.map3d = null;
    this.map2d = null;
    this.markers3d.clear();
    this.markers2d.forEach((m) => {
      try {
        m.setMap(null);
      } catch {}
    });
    this.markers2d.clear();
    this.selectedPolygon2d = null;
    this.mode = null;
  }

  private async bootstrap(globeEl: HTMLElement): Promise<void> {
    try {
      const google = await this.ensureGoogleMaps();
      this.google = google;

      // Prefer true 3D photorealistic globe
      try {
        await this.mountMap3D(globeEl, google);
      } catch (err) {
        console.warn('[globe] Map3D unavailable, falling back to vector globe map', err);
        await this.mountMap2DVectorGlobe(globeEl, google);
      }

      this.settleReady();
      if (this.cachedPayload) this.setDataFast(this.cachedPayload);
      if (this.cachedConnections.length) this.setConnections(this.cachedConnections);
    } catch (err: any) {
      console.warn('[globe] Google Maps failed', err);
      this.showKeyMissing(globeEl, err?.message || String(err));
      this.settleReady();
    }
  }

  private settleReady(): void {
    if (this.readySettled) return;
    this.readySettled = true;
    this.readyResolver?.();
  }

  private showKeyMissing(el: HTMLElement, detail = ''): void {
    el.innerHTML = '';
    const box = document.createElement('div');
    box.style.cssText =
      'position:absolute;inset:0;display:grid;place-items:center;padding:24px;text-align:center;color:#e8eef8;background:#000810;font-family:system-ui,sans-serif;';
    box.innerHTML = `
      <div style="max-width:460px">
        <div style="font-size:18px;font-weight:700;margin-bottom:8px">Google 3D Globe needs an API key</div>
        <div style="font-size:13px;opacity:.8;line-height:1.45;margin-bottom:14px">
          Enable <b>Maps JavaScript API</b> (and Map Tiles API if prompted for 3D).
          Restrict the key to your domain.
        </div>
        <input id="gmaps-key-input" type="password" placeholder="Paste Google Maps API key"
          style="width:100%;box-sizing:border-box;padding:10px 12px;border-radius:10px;border:1px solid rgba(255,255,255,.15);background:rgba(255,255,255,.06);color:#fff;margin-bottom:10px" />
        <button id="gmaps-key-save" type="button"
          style="border:0;border-radius:10px;padding:10px 14px;background:#7b6347;color:#f8f6f2;font-weight:700;cursor:pointer">
          Save & load 3D globe
        </button>
        ${detail ? `<div style="margin-top:10px;font-size:12px;opacity:.55">${detail}</div>` : ''}
      </div>`;
    el.appendChild(box);
    const input = box.querySelector('#gmaps-key-input') as HTMLInputElement | null;
    const btn = box.querySelector('#gmaps-key-save') as HTMLButtonElement | null;
    btn?.addEventListener('click', () => {
      const key = (input?.value || '').trim();
      if (!key) return;
      try {
        localStorage.setItem('matterya_google_maps_key', key);
      } catch {}
      (window as any).MATTERYA_GOOGLE_MAPS_KEY = key;
      el.innerHTML = '';
      this.readySettled = false;
      this.readyPromise = new Promise<void>((resolve) => {
        this.readyResolver = resolve;
      });
      this.init(el);
    });
  }

  /** Photorealistic 3D Earth sphere (Google maps3d). */
  private async mountMap3D(el: HTMLElement, google: any): Promise<void> {
    el.innerHTML = '';
    const host = document.createElement('div');
    host.style.cssText = 'position:absolute;inset:0;width:100%;height:100%';
    el.appendChild(host);

    const maps3d = await google.maps.importLibrary('maps3d');
    this.maps3dLib = maps3d;
    const { Map3DElement, MapMode } = maps3d;
    if (!Map3DElement) throw new Error('Map3DElement missing');

    const map3d = new Map3DElement({
      mode: MapMode?.HYBRID ?? 'HYBRID',
      center: { lat: 20, lng: 10, altitude: 0 },
      // Camera distance from Earth center target — full globe like iOS
      range: this.GLOBE_RANGE_M,
      tilt: 0,
      heading: 0,
      roll: 0,
    });

    // Fill container
    map3d.style.cssText = 'width:100%;height:100%;display:block;';
    // Custom element must be in DOM
    host.appendChild(map3d);
    this.map3d = map3d;
    this.mode = '3d';

    // Click → country
    const onClick = (ev: any) => {
      if (!this.interactive || this.renderingPaused) return;
      const pos = ev?.position || ev?.detail?.position || ev?.latLng;
      const lat = Number(pos?.lat ?? pos?.latitude);
      const lng = Number(pos?.lng ?? pos?.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      const found = this.hitTestCountry(lat, lng);
      if (!found) return;
      this.selectCountry(found.id);
      this.countryClickCb?.(found);
      this.flyTo(found.center.lat, found.center.lng, found.flyAltitude ?? 1.0, 900);
    };

    // Map3D supports gmp-click in recent versions; also listen to click.
    map3d.addEventListener('gmp-click', onClick as any);
    map3d.addEventListener('click', onClick as any);

    // iOS MapKit: one finger rotates/orbits, pinch (two fingers) zooms only.
    // Disable built-in multi-touch rotate by owning gestures ourselves.
    try {
      map3d.gestureHandling = 'none';
    } catch {}
    this.installIosStyleGestures(host, map3d);
  }

  /**
   * Fallback: classic Map with VECTOR rendering + mapId → sphere when zoomed out.
   * Still more “globe-like” than raster mercator hybrid.
   */
  private async mountMap2DVectorGlobe(el: HTMLElement, google: any): Promise<void> {
    el.innerHTML = '';
    const mapDiv = document.createElement('div');
    mapDiv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%';
    el.appendChild(mapDiv);

    const mapId =
      (environment as any).googleMapsMapId ||
      (window as any).MATTERYA_GOOGLE_MAP_ID ||
      'DEMO_MAP_ID';

    const map = new google.maps.Map(mapDiv, {
      center: { lat: 20, lng: 10 },
      zoom: 2,
      minZoom: 1,
      maxZoom: 18,
      mapId,
      mapTypeId: 'hybrid',
      disableDefaultUI: true,
      clickableIcons: false,
      keyboardShortcuts: false,
      gestureHandling: this.interactive ? 'greedy' : 'none',
      backgroundColor: '#000810',
      isFractionalZoomEnabled: true,
      tilt: 45,
      heading: 0,
      renderingType: google.maps.RenderingType?.VECTOR ?? undefined,
    });

    try {
      map.setMapTypeId(google.maps.MapTypeId.HYBRID);
    } catch {}

    this.map2d = map;
    this.mode = '2d';

    map.addListener('click', (ev: any) => {
      if (!this.interactive || this.renderingPaused) return;
      const lat = ev?.latLng?.lat?.();
      const lng = ev?.latLng?.lng?.();
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      const found = this.hitTestCountry(lat, lng);
      if (!found) return;
      this.selectCountry(found.id);
      this.countryClickCb?.(found);
      this.flyTo(found.center.lat, found.center.lng, found.flyAltitude ?? 1.0, 700);
    });
  }


  /**
   * iOS MapKit globe gestures:
   * - 1 finger drag → orbit / spin the globe
   * - 2 finger pinch → zoom (range) only
   */
  private installIosStyleGestures(host: HTMLElement, map3d: any): void {
    this.unbindGestures?.();
    this.gestureHost = host;

    const syncFromMap = () => {
      try {
        const c = map3d.center || {};
        this.gestureCenterLat = Number(c.lat ?? this.gestureCenterLat);
        this.gestureCenterLng = Number(c.lng ?? this.gestureCenterLng);
        this.gestureRange = Number(map3d.range ?? this.gestureRange);
        this.gestureHeading = Number(map3d.heading ?? this.gestureHeading);
        this.gestureTilt = Number(map3d.tilt ?? this.gestureTilt);
      } catch {}
    };
    syncFromMap();

    const applyCamera = () => {
      this.gestureCenterLat = Math.max(-85, Math.min(85, this.gestureCenterLat));
      let lng = this.gestureCenterLng;
      while (lng > 180) lng -= 360;
      while (lng < -180) lng += 360;
      this.gestureCenterLng = lng;
      this.gestureRange = Math.max(250_000, Math.min(80_000_000, this.gestureRange));
      this.gestureTilt = Math.max(0, Math.min(85, this.gestureTilt));
      try {
        map3d.center = {
          lat: this.gestureCenterLat,
          lng: this.gestureCenterLng,
          altitude: 0,
        };
        map3d.range = this.gestureRange;
        map3d.heading = this.gestureHeading;
        map3d.tilt = this.gestureTilt;
      } catch {}
    };

    const dist = (a: Touch, b: Touch) => {
      const dx = a.clientX - b.clientX;
      const dy = a.clientY - b.clientY;
      return Math.hypot(dx, dy);
    };

    const onTouchStart = (ev: TouchEvent) => {
      if (!this.interactive || this.renderingPaused) return;
      syncFromMap();
      if (ev.touches.length === 1) {
        this.touchMode = 'orbit';
        this.lastTouchX = ev.touches[0].clientX;
        this.lastTouchY = ev.touches[0].clientY;
      } else if (ev.touches.length >= 2) {
        this.touchMode = 'pinch';
        this.lastPinchDist = dist(ev.touches[0], ev.touches[1]);
        ev.preventDefault();
      }
    };

    const onTouchMove = (ev: TouchEvent) => {
      if (!this.interactive || this.renderingPaused) return;
      if (this.touchMode === 'orbit' && ev.touches.length === 1) {
        ev.preventDefault();
        const t = ev.touches[0];
        const dx = t.clientX - this.lastTouchX;
        const dy = t.clientY - this.lastTouchY;
        this.lastTouchX = t.clientX;
        this.lastTouchY = t.clientY;
        const rangeFactor = Math.max(0.15, Math.min(2.5, this.gestureRange / this.GLOBE_RANGE_M));
        // One finger: spin/orbit globe (MapKit style)
        this.gestureCenterLng -= dx * 0.18 * rangeFactor;
        this.gestureCenterLat += dy * 0.14 * rangeFactor;
        applyCamera();
      } else if (ev.touches.length >= 2) {
        // Two fingers: zoom only
        ev.preventDefault();
        this.touchMode = 'pinch';
        const d = dist(ev.touches[0], ev.touches[1]);
        if (this.lastPinchDist > 0) {
          const scale = this.lastPinchDist / d;
          this.gestureRange *= scale;
          applyCamera();
        }
        this.lastPinchDist = d;
      }
    };

    const onTouchEnd = (ev: TouchEvent) => {
      if (ev.touches.length === 0) {
        this.touchMode = 'none';
        this.lastPinchDist = 0;
      } else if (ev.touches.length === 1) {
        this.touchMode = 'orbit';
        this.lastTouchX = ev.touches[0].clientX;
        this.lastTouchY = ev.touches[0].clientY;
        this.lastPinchDist = 0;
      }
    };

    let mouseOrbit = false;
    const onMouseDown = (ev: MouseEvent) => {
      if (!this.interactive || this.renderingPaused) return;
      if (ev.button !== 0) return;
      syncFromMap();
      mouseOrbit = true;
      this.lastTouchX = ev.clientX;
      this.lastTouchY = ev.clientY;
    };
    const onMouseMove = (ev: MouseEvent) => {
      if (!mouseOrbit || !this.interactive) return;
      const dx = ev.clientX - this.lastTouchX;
      const dy = ev.clientY - this.lastTouchY;
      this.lastTouchX = ev.clientX;
      this.lastTouchY = ev.clientY;
      const rangeFactor = Math.max(0.15, Math.min(2.5, this.gestureRange / this.GLOBE_RANGE_M));
      this.gestureCenterLng -= dx * 0.18 * rangeFactor;
      this.gestureCenterLat += dy * 0.14 * rangeFactor;
      applyCamera();
    };
    const onMouseUp = () => {
      mouseOrbit = false;
    };
    const onWheel = (ev: WheelEvent) => {
      if (!this.interactive || this.renderingPaused) return;
      ev.preventDefault();
      syncFromMap();
      const factor = ev.deltaY > 0 ? 1.08 : 1 / 1.08;
      this.gestureRange *= factor;
      applyCamera();
    };

    const opts: AddEventListenerOptions = { capture: true, passive: false };
    host.addEventListener('touchstart', onTouchStart, opts);
    host.addEventListener('touchmove', onTouchMove, opts);
    host.addEventListener('touchend', onTouchEnd, opts);
    host.addEventListener('touchcancel', onTouchEnd, opts);
    host.addEventListener('mousedown', onMouseDown, opts);
    window.addEventListener('mousemove', onMouseMove, true);
    window.addEventListener('mouseup', onMouseUp, true);
    host.addEventListener('wheel', onWheel, opts);
    host.style.touchAction = 'none';

    this.unbindGestures = () => {
      host.removeEventListener('touchstart', onTouchStart, opts);
      host.removeEventListener('touchmove', onTouchMove, opts);
      host.removeEventListener('touchend', onTouchEnd, opts);
      host.removeEventListener('touchcancel', onTouchEnd, opts);
      host.removeEventListener('mousedown', onMouseDown, opts);
      window.removeEventListener('mousemove', onMouseMove, true);
      window.removeEventListener('mouseup', onMouseUp, true);
      host.removeEventListener('wheel', onWheel, opts);
    };
  }

  private async ensureGoogleMaps(): Promise<any> {
    const w = window as any;
    if (w.google?.maps?.importLibrary) return w.google;

    const key =
      (environment as any).googleMapsApiKey ||
      w.MATTERYA_GOOGLE_MAPS_KEY ||
      localStorage.getItem('matterya_google_maps_key') ||
      '';
    if (!String(key).trim()) throw new Error('Missing googleMapsApiKey');

    // v=weekly includes maps3d; importLibrary('maps3d') loads 3D globe
    await this.loadScript(
      `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&v=weekly&loading=async`
    );
    if (!w.google?.maps?.importLibrary) {
      throw new Error('Google Maps loaded without importLibrary');
    }
    return w.google;
  }

  private loadScript(src: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const existing = document.querySelector(
        'script[src^="https://maps.googleapis.com/maps/api/js"]'
      ) as HTMLScriptElement | null;
      if (existing) {
        if ((window as any).google?.maps) {
          resolve();
          return;
        }
        existing.addEventListener('load', () => resolve());
        existing.addEventListener('error', () => reject(new Error('Google Maps script failed')));
        return;
      }
      const s = document.createElement('script');
      s.src = src;
      s.async = true;
      s.defer = true;
      s.onload = () => resolve();
      s.onerror = () => reject(new Error('Failed to load Google Maps JS'));
      document.head.appendChild(s);
    });
  }

  resize(): void {
    // Map3D / Map fill CSS; no explicit resize API needed beyond reflow
    if (this.mode === '2d' && this.map2d && this.google) {
      try {
        this.google.maps.event.trigger(this.map2d, 'resize');
      } catch {}
    }
  }

  onCountryClick(cb: (country: CountryModel) => void): void {
    this.countryClickCb = cb;
  }

  whenReady(): Promise<void> {
    return this.readyPromise;
  }

  setInteractive(enabled: boolean): void {
    this.interactive = enabled;
    if (this.mode === '3d' && this.map3d) {
      // Always custom gestures for 3d; just gate via this.interactive
      try {
        this.map3d.gestureHandling = 'none';
      } catch {}
    }
    if (this.mode === '2d' && this.map2d) {
      this.map2d.setOptions({
        gestureHandling: enabled ? 'greedy' : 'none',
        draggable: enabled,
        scrollwheel: enabled,
      });
    }
  }

  pauseRendering(): void {
    this.renderingPaused = true;
  }

  resumeRendering(): void {
    this.renderingPaused = false;
    this.resize();
  }

  setData(payload: CountriesPayload): void {
    this.setDataFast(payload);
  }

  restoreCachedDataIfAny(): void {
    if (this.cachedPayload) this.setDataFast(this.cachedPayload);
  }

  setDataFast(payload: CountriesPayload): void {
    this.cachedPayload = payload;
    this.countries = payload?.countries || [];
    this.features = payload?.features || [];
  }

  setConnections(points: ConnectionPoint[]): void {
    this.cachedConnections = points || [];
    this.syncMarkers();
  }

  setConnectionOnline(id: string | number, online: boolean): void {
    const key = String(id);
    if (online) this.onlineConnectionIds.add(key);
    else this.onlineConnectionIds.delete(key);
    this.syncMarkers();
  }

  setConnectionsOnline(idsOnline: Array<string | number>): void {
    this.onlineConnectionIds = new Set((idsOnline || []).map((x) => String(x)));
    this.syncMarkers();
  }

  setFloatingWords(_words: string[]): void {}
  setFireworkWordGroups(_groups: string[][]): void {}
  setConnectionsCountryFilter(_iso2: string | null): void {}
  showAllLabels(): void {}
  showFocusLabel(_countryId: number): void {}
  setSoloCountry(_countryId: number | null): void {}
  setViewPadding(_padding: any): void {}
  resetViewPadding(): void {}

  selectCountry(countryId: number | null): void {
    this.selectedId = countryId;
    if (this.mode === '2d') this.drawSelectedOutline2d(countryId);
  }

  flyTo(lat: number, lng: number, altitudeOrZoom: number, ms = 900): void {
    const range = this.altitudeToRange(altitudeOrZoom);
    this.gestureCenterLat = lat;
    this.gestureCenterLng = lng;
    this.gestureRange = range;

    if (this.mode === '3d' && this.map3d) {
      const endCamera = {
        center: { lat, lng, altitude: 0 },
        range,
        tilt: range < 8_000_000 ? 55 : 15,
        heading: 0,
      };
      try {
        if (typeof this.map3d.flyCameraTo === 'function') {
          this.map3d.flyCameraTo({
            endCamera,
            durationMillis: Math.max(200, ms),
          });
          return;
        }
      } catch {}
      // property assignment fallback
      try {
        this.map3d.center = endCamera.center;
        this.map3d.range = endCamera.range;
        this.map3d.tilt = endCamera.tilt;
        this.map3d.heading = endCamera.heading;
      } catch {}
      return;
    }

    if (this.mode === '2d' && this.map2d) {
      const zoom = this.rangeToZoom(range);
      this.map2d.panTo({ lat, lng });
      this.map2d.setZoom(zoom);
      try {
        this.map2d.setTilt(range < 8_000_000 ? 45 : 0);
      } catch {}
    }
  }

  resetView(): void {
    this.gestureCenterLat = 20;
    this.gestureCenterLng = 10;
    this.gestureRange = this.GLOBE_RANGE_M;
    this.gestureHeading = 0;
    this.gestureTilt = 0;
    if (this.mode === '3d' && this.map3d) {
      try {
        if (typeof this.map3d.flyCameraTo === 'function') {
          this.map3d.flyCameraTo({
            endCamera: {
              center: { lat: 20, lng: 10, altitude: 0 },
              range: this.GLOBE_RANGE_M,
              tilt: 0,
              heading: 0,
            },
            durationMillis: 900,
          });
        } else {
          this.map3d.center = { lat: 20, lng: 10, altitude: 0 };
          this.map3d.range = this.GLOBE_RANGE_M;
          this.map3d.tilt = 0;
          this.map3d.heading = 0;
        }
      } catch {}
      return;
    }
    if (this.mode === '2d' && this.map2d) {
      this.map2d.panTo({ lat: 20, lng: 10 });
      this.map2d.setZoom(2);
      try {
        this.map2d.setTilt(0);
        this.map2d.setHeading(0);
      } catch {}
    }
  }

  private altitudeToRange(altitude: number): number {
    if (!Number.isFinite(altitude) || altitude <= 0) return this.FOCUS_RANGE_M;
    // Prior Cesium-ish altitude scale → camera range meters
    if (altitude >= 2) return 12_000_000;
    if (altitude >= 1) return this.FOCUS_RANGE_M;
    if (altitude >= 0.5) return 1_600_000;
    return 900_000;
  }

  private rangeToZoom(range: number): number {
    if (range >= 20_000_000) return 2;
    if (range >= 8_000_000) return 3.5;
    if (range >= 3_000_000) return 5;
    if (range >= 1_500_000) return 6;
    return 7;
  }

  private syncMarkers(): void {
    if (this.mode === '3d') {
      void this.syncMarkers3d();
      return;
    }
    this.syncMarkers2d();
  }

  private async syncMarkers3d(): Promise<void> {
    if (!this.map3d || !this.maps3dLib) return;
    const Marker3D =
      this.maps3dLib.Marker3DElement ||
      this.maps3dLib.Marker3DInteractiveElement ||
      null;

    const wanted = new Set<string>();
    for (const p of this.cachedConnections) {
      if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng)) continue;
      const id = String(p.id);
      if (this.onlineConnectionIds.size && !this.onlineConnectionIds.has(id)) continue;
      wanted.add(id);

      let marker = this.markers3d.get(id);
      if (!marker && Marker3D) {
        try {
          marker = new Marker3D({
            position: { lat: p.lat, lng: p.lng, altitude: 0 },
            altitudeMode: 'CLAMP_TO_GROUND',
          });
          // simple pin color via CSS if supported
          try {
            (marker as any).style = 'color:#7cf0ff';
          } catch {}
          this.map3d.append(marker);
          this.markers3d.set(id, marker);
        } catch {
          // ignore marker failures
        }
      } else if (marker) {
        try {
          marker.position = { lat: p.lat, lng: p.lng, altitude: 0 };
        } catch {}
      }
    }

    for (const [id, marker] of this.markers3d) {
      if (!wanted.has(id)) {
        try {
          marker.remove?.();
        } catch {}
        this.markers3d.delete(id);
      }
    }
  }

  private syncMarkers2d(): void {
    if (!this.map2d || !this.google) return;
    const g = this.google;
    const wanted = new Set<string>();

    for (const p of this.cachedConnections) {
      if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng)) continue;
      const id = String(p.id);
      if (this.onlineConnectionIds.size && !this.onlineConnectionIds.has(id)) continue;
      wanted.add(id);

      let marker = this.markers2d.get(id);
      if (!marker) {
        marker = new g.maps.Marker({
          map: this.map2d,
          position: { lat: p.lat, lng: p.lng },
          clickable: false,
          icon: {
            path: g.maps.SymbolPath.CIRCLE,
            scale: Math.max(3, Number(p.radius) || 4),
            fillColor: p.color || '#7cf0ff',
            fillOpacity: 0.9,
            strokeColor: '#ffffff',
            strokeWeight: 1,
          },
        });
        this.markers2d.set(id, marker);
      } else {
        marker.setPosition({ lat: p.lat, lng: p.lng });
        marker.setMap(this.map2d);
      }
    }

    for (const [id, marker] of this.markers2d) {
      if (!wanted.has(id)) {
        marker.setMap(null);
        this.markers2d.delete(id);
      }
    }
  }

  private drawSelectedOutline2d(countryId: number | null): void {
    if (!this.map2d || !this.google) return;
    if (this.selectedPolygon2d) {
      this.selectedPolygon2d.setMap(null);
      this.selectedPolygon2d = null;
    }
    if (countryId == null) return;
    const feature = this.features.find((f) => {
      const props = f?.properties || {};
      const id = Number(f?.__id ?? props.__id ?? props.id);
      return id === countryId;
    });
    if (!feature?.geometry) return;
    const paths = this.geometryToPaths(feature.geometry);
    if (!paths.length) return;
    this.selectedPolygon2d = new this.google.maps.Polygon({
      paths: paths.length === 1 ? paths[0] : paths,
      map: this.map2d,
      strokeColor: '#f5d76e',
      strokeOpacity: 0.95,
      strokeWeight: 2,
      fillColor: '#f5d76e',
      fillOpacity: 0.08,
      clickable: false,
    });
  }

  private geometryToPaths(geometry: any): any[] {
    if (!geometry) return [];
    if (geometry.type === 'Polygon') {
      return [geometry.coordinates[0].map(([lng, lat]: number[]) => ({ lat, lng }))];
    }
    if (geometry.type === 'MultiPolygon') {
      return geometry.coordinates.map((poly: any) =>
        poly[0].map(([lng, lat]: number[]) => ({ lat, lng }))
      );
    }
    return [];
  }

  private hitTestCountry(lat: number, lng: number): CountryModel | null {
    for (const f of this.features) {
      const props = f?.properties || {};
      const id = Number(f?.__id ?? props.__id ?? props.id);
      if (!Number.isFinite(id) || !f?.geometry) continue;
      if (this.pointInGeometry(lng, lat, f.geometry)) {
        const found = this.countries.find((c) => Number(c.id) === id);
        if (found) return found;
      }
    }
    let best: CountryModel | null = null;
    let bestD = Infinity;
    for (const c of this.countries) {
      const clat = Number(c.center?.lat);
      const clng = Number(c.center?.lng);
      if (!Number.isFinite(clat) || !Number.isFinite(clng)) continue;
      const d = (clat - lat) * (clat - lat) + (clng - lng) * (clng - lng);
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return bestD < 25 ? best : null;
  }

  private pointInGeometry(lng: number, lat: number, geometry: any): boolean {
    if (!geometry) return false;
    if (geometry.type === 'Polygon') return this.pointInPolygon(lng, lat, geometry.coordinates);
    if (geometry.type === 'MultiPolygon') {
      return geometry.coordinates.some((poly: any) => this.pointInPolygon(lng, lat, poly));
    }
    return false;
  }

  private pointInPolygon(lng: number, lat: number, polygon: number[][][]): boolean {
    if (!polygon?.length) return false;
    const inRing = (ring: number[][]) => {
      let inside = false;
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        const xi = ring[i][0];
        const yi = ring[i][1];
        const xj = ring[j][0];
        const yj = ring[j][1];
        const intersect =
          yi > lat !== yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi + 0.0) + xi;
        if (intersect) inside = !inside;
      }
      return inside;
    };
    if (!inRing(polygon[0])) return false;
    for (let h = 1; h < polygon.length; h++) {
      if (inRing(polygon[h])) return false;
    }
    return true;
  }
}
