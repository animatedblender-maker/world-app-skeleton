
// MapLibre-backed service (SAME service name + API)
//
// ✅ Infinite-looking ocean: world copies ON
// ✅ Fullscreen-safe: forces map.resize() after load
// ✅ Click/search: centers + zooms (with padding for your topbar)
// ✅ Labels: exactly one per country (point source from countries[].center)
// ✅ Connections: floating points = user connections (feature-state for online)
//
// IMPORTANT: No hover -> NO pill updates. Only click/search triggers selection.

import { Injectable } from '@angular/core';
import { continentColors, oceanColor } from './palette';
import type { CountryModel } from '../data/countries.service';

import maplibregl, { Map as MLMap, GeoJSONSource, MapMouseEvent } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';

type CountriesPayload = { features: any[]; countries: CountryModel[] };
type CountriesFeature = GeoJSON.Feature<GeoJSON.Geometry, any> & { id?: number };

/** Connection point model (your "floating dots") */
export type ConnectionPoint = {
  id: string | number;
  lat: number;
  lng: number;
  color?: string;
  radius?: number;
};

@Injectable({ providedIn: 'root' })
export class GlobeService {
  private map: MLMap | null = null;

  private features: CountriesFeature[] = [];
  private countries: CountryModel[] = [];
  private selectedId: number | null = null;

  private countryClickCb: ((country: CountryModel) => void) | null = null;
  private cachedPayload: CountriesPayload | null = null;

  // --- Sources / layers ---
  private readonly COUNTRIES_SOURCE = 'worldapp-countries';
  private readonly FILL_LAYER = 'worldapp-fill';
  private readonly LINE_LAYER = 'worldapp-line';

  private readonly LABEL_SOURCE = 'worldapp-country-labels';
  private readonly LABEL_LAYER = 'worldapp-labels';

  private readonly CONN_SOURCE = 'worldapp-connections';
  private readonly CONN_LAYER = 'worldapp-connections-layer';
  private cachedConnections: ConnectionPoint[] = [];

  private readonly ONLINE_COLOR = 'rgba(0,255,120,0.98)';
  private readonly OFFLINE_ALPHA = 0.85;

  // --- Mystical overlay ---
  private overlayHost: HTMLElement | null = null;
  private auraEl: HTMLDivElement | null = null;
  private grainEl: HTMLDivElement | null = null;
  private particleCanvas: HTMLCanvasElement | null = null;
  private particleCtx: CanvasRenderingContext2D | null = null;
  private raf = 0;

  private readonly MIN_LABEL_SIZE_PX = 12;
  private readonly MAX_LABEL_SIZE_PX = 18;

  private readonly VIEW_PADDING = { top: 90, bottom: 20, left: 20, right: 20 };

  init(globeEl: HTMLElement): void {
    const cs = getComputedStyle(globeEl);
    if (cs.position === 'static') globeEl.style.position = 'relative';

    globeEl.style.background = oceanColor;

    const style: any = {
      version: 8,
      sources: {},
      layers: [{ id: 'bg', type: 'background', paint: { 'background-color': oceanColor } }],
    };

    const map = new maplibregl.Map({
      container: globeEl,
      style,
      center: [0, 20],
      zoom: 1.35,
      minZoom: 1.05,
      maxZoom: 6.2,
      attributionControl: false,
      dragRotate: false,
      pitchWithRotate: false,
    });

    map.dragRotate.disable();
    map.touchZoomRotate.disableRotation();

    try { map.setRenderWorldCopies(true); } catch {}
    try { (map.getCanvas().parentElement as HTMLElement).style.background = oceanColor; } catch {}

    this.installMysticOverlay(globeEl);

    map.on('load', () => {
      this.map = map;

      requestAnimationFrame(() => map.resize());
      setTimeout(() => map.resize(), 0);
      setTimeout(() => map.resize(), 80);

      // ✅ ONLY click selection (no hover logic)
      map.on('click', this.FILL_LAYER, (e) => this.onCountryClickInternal(e));
      map.on('mouseenter', this.FILL_LAYER, () => (map.getCanvas().style.cursor = 'pointer'));
      map.on('mouseleave', this.FILL_LAYER, () => (map.getCanvas().style.cursor = ''));

      if (this.cachedPayload) this.setDataFast(this.cachedPayload);
      if (this.cachedConnections.length) this.setConnections(this.cachedConnections);

      this.startOverlayLoop();
    });

    window.addEventListener('resize', () => {
      try { map.resize(); } catch {}
      this.resizeParticles();
    });
  }

  onCountryClick(cb: (country: CountryModel) => void) {
    this.countryClickCb = cb;
  }

  setData(payload: CountriesPayload): void {
    this.setDataFast(payload);
  }

  restoreCachedDataIfAny(): void {
    if (this.cachedPayload) this.setDataFast(this.cachedPayload);
  }

  setDataFast(payload: CountriesPayload): void {
    if (!this.map) {
      this.cachedPayload = payload;
      return;
    }

    this.cachedPayload = payload;
    this.countries = payload.countries || [];

    const normalized: CountriesFeature[] = (payload.features || []).map((f: any) => {
      const props = (f.properties ??= {});
      const rawId = f.__id ?? props.__id ?? props.id;
      const id = Number(rawId);

      props.__id = Number.isFinite(id) ? id : undefined;
      props.fill = this.fillForProps(props);

      return {
        type: 'Feature',
        geometry: f.geometry,
        properties: props,
        id: props.__id,
      };
    });

    this.features = normalized;

    const countriesFC: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: this.features,
    };

    const uniqueCountries = this.uniqueCountriesById(this.countries);
    const labelsFC: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: uniqueCountries
        .filter((c) => Number.isFinite(c.center?.lat) && Number.isFinite(c.center?.lng))
        .map((c) => {
          const base = 12 + (c.labelSize ?? 1) * 2;
          const size = Math.max(this.MIN_LABEL_SIZE_PX, Math.min(this.MAX_LABEL_SIZE_PX, base));
          return {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [c.center.lng, c.center.lat] },
            properties: { id: c.id, name: c.name, labelSize: size },
            id: c.id,
          } as GeoJSON.Feature<GeoJSON.Point, any>;
        }),
    };

    const map = this.map;

    const countriesSrc = map.getSource(this.COUNTRIES_SOURCE) as GeoJSONSource | undefined;
    if (!countriesSrc) {
      map.addSource(this.COUNTRIES_SOURCE, { type: 'geojson', data: countriesFC });

      map.addLayer({
        id: this.FILL_LAYER,
        type: 'fill',
        source: this.COUNTRIES_SOURCE,
        paint: {
          'fill-color': [
            'case',
            ['boolean', ['feature-state', 'selected'], false],
            'rgba(255,255,255,0.35)',
            ['get', 'fill'],
          ],
          'fill-opacity': 1.0,
        },
      });

      map.addLayer({
        id: this.LINE_LAYER,
        type: 'line',
        source: this.COUNTRIES_SOURCE,
        paint: { 'line-color': 'rgba(255,255,255,0.22)', 'line-width': 1 },
      });
    } else {
      countriesSrc.setData(countriesFC);
    }

    const labelsSrc = map.getSource(this.LABEL_SOURCE) as GeoJSONSource | undefined;
    if (!labelsSrc) {
      map.addSource(this.LABEL_SOURCE, { type: 'geojson', data: labelsFC });

      map.addLayer({
        id: this.LABEL_LAYER,
        type: 'symbol',
        source: this.LABEL_SOURCE,
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
          'text-size': ['coalesce', ['get', 'labelSize'], 13],
          'text-anchor': 'center',
          'symbol-placement': 'point',
          'text-allow-overlap': false,
          'text-ignore-placement': false,
        },
        paint: {
          'text-color': 'rgba(255,255,255,0.94)',
          'text-halo-color': 'rgba(0,0,0,0.45)',
          'text-halo-width': 1.2,
        },
      });

      this.showAllLabels();
    } else {
      labelsSrc.setData(labelsFC);
    }

    this.selectedId = null;
    this.bumpAura();
  }

  // -----------------------------
  // Connections
  // -----------------------------

  setConnections(points: ConnectionPoint[]): void {
    this.cachedConnections = points || [];
    if (!this.map) return;

    const features: GeoJSON.Feature<GeoJSON.Point, any>[] = (points || [])
      .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lng))
      .map((p) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
        properties: {
          id: String(p.id),
          baseColor: p.color ?? 'rgba(160,220,255,0.85)',
          r: typeof p.radius === 'number' ? p.radius : 3.4,
        },
        id: String(p.id),
      }));

    const fc: GeoJSON.FeatureCollection = { type: 'FeatureCollection', features };

    const map = this.map;
    const src = map.getSource(this.CONN_SOURCE) as GeoJSONSource | undefined;

    if (!src) {
      map.addSource(this.CONN_SOURCE, { type: 'geojson', data: fc });

      const beforeLayer = this.LABEL_LAYER;

      map.addLayer(
        {
          id: this.CONN_LAYER,
          type: 'circle',
          source: this.CONN_SOURCE,
          paint: {
            'circle-color': [
              'case',
              ['boolean', ['feature-state', 'online'], false],
              this.ONLINE_COLOR,
              ['get', 'baseColor'],
            ],
            'circle-opacity': [
              'case',
              ['boolean', ['feature-state', 'online'], false],
              1.0,
              this.OFFLINE_ALPHA,
            ],
            'circle-radius': ['coalesce', ['get', 'r'], 3.4],
            'circle-stroke-color': [
              'case',
              ['boolean', ['feature-state', 'online'], false],
              'rgba(0,255,160,0.85)',
              'rgba(255,255,255,0.18)',
            ],
            'circle-stroke-width': [
              'case',
              ['boolean', ['feature-state', 'online'], false],
              1.6,
              0.8,
            ],
            'circle-blur': [
              'case',
              ['boolean', ['feature-state', 'online'], false],
              0.35,
              0.20,
            ],
          },
        },
        beforeLayer
      );
    } else {
      src.setData(fc);
    }
  }

  setConnectionOnline(id: string | number, online: boolean): void {
    if (!this.map) return;
    const key = String(id);
    try { this.map.setFeatureState({ source: this.CONN_SOURCE, id: key }, { online: !!online }); } catch {}
  }

  setConnectionsOnline(idsOnline: Array<string | number>): void {
    if (!this.map) return;
    const set = new globalThis.Set<string>((idsOnline || []).map((x) => String(x)));

    for (const p of this.cachedConnections) {
      const key = String(p.id);
      const online = set.has(key);
      try { this.map.setFeatureState({ source: this.CONN_SOURCE, id: key }, { online }); } catch {}
    }
  }

  // -----------------------------
  // Labels control (compat)
  // -----------------------------

  showAllLabels(): void {
    if (!this.map) return;
    try { this.map.setFilter(this.LABEL_LAYER, null as any); } catch {}
  }

  showFocusLabel(countryId: number): void {
    if (!this.map) return;
    try { this.map.setFilter(this.LABEL_LAYER, ['==', ['get', 'id'], countryId] as any); } catch {}
  }

  // -----------------------------
  // Country selection / camera
  // -----------------------------

  selectCountry(countryId: number | null): void {
    if (!this.map) return;

    if (this.selectedId != null) {
      try { this.map.setFeatureState({ source: this.COUNTRIES_SOURCE, id: this.selectedId }, { selected: false }); } catch {}
    }

    this.selectedId = countryId;

    if (countryId != null) {
      try { this.map.setFeatureState({ source: this.COUNTRIES_SOURCE, id: countryId }, { selected: true }); } catch {}
    }

    this.bumpAura(true);
  }

  flyTo(lat: number, lng: number, altitudeOrZoom: number, ms = 900): void {
    if (!this.map) return;

    const zoom = this.altitudeToZoom(altitudeOrZoom);

    this.map.flyTo({
      center: [lng, lat],
      zoom,
      duration: ms,
      essential: true,
      padding: this.VIEW_PADDING,
    });

    this.bumpAura();
  }

  resetView(): void {
    this.selectCountry(null);
    this.showAllLabels();
    if (!this.map) return;

    this.map.flyTo({
      center: [0, 20],
      zoom: 1.35,
      duration: 800,
      essential: true,
      padding: this.VIEW_PADDING,
    });

    this.bumpAura();
  }

  private onCountryClickInternal(e: MapMouseEvent): void {
    if (!this.map) return;

    const hits = this.map.queryRenderedFeatures(e.point, { layers: [this.FILL_LAYER] }) as any[];
    const f = hits?.[0];
    const id = Number(f?.id ?? f?.properties?.__id);

    if (!Number.isFinite(id)) return;

    const found = this.countries.find((c) => c.id === id);
    if (!found) return;

    this.selectCountry(found.id);
    this.flyTo(found.center.lat, found.center.lng, found.flyAltitude ?? 1.0, 900);
    this.showFocusLabel(found.id);

    this.countryClickCb?.(found);
  }

  // -----------------------------
  // Mystical overlay
  // -----------------------------

  private installMysticOverlay(host: HTMLElement) {
    this.overlayHost = host;

    const aura = document.createElement('div');
    aura.style.position = 'absolute';
    aura.style.inset = '0';
    aura.style.pointerEvents = 'none';
    aura.style.zIndex = '2';
    aura.style.mixBlendMode = 'screen';
    aura.style.opacity = '0.9';
    aura.style.background =
      `radial-gradient(900px 700px at 50% 30%, rgba(102,191,255,0.18), transparent 60%),
       radial-gradient(900px 800px at 58% 76%, rgba(140,0,255,0.10), transparent 62%),
       radial-gradient(1100px 900px at 50% 55%, rgba(102,191,255,0.06), transparent 68%)`;
    aura.style.filter = 'blur(0px)';
    aura.style.transition = 'opacity 450ms ease, filter 650ms ease';
    host.appendChild(aura);
    this.auraEl = aura;

    const grain = document.createElement('div');
    grain.style.position = 'absolute';
    grain.style.inset = '0';
    grain.style.pointerEvents = 'none';
    grain.style.zIndex = '3';
    grain.style.opacity = '0.10';
    grain.style.mixBlendMode = 'overlay';
    grain.style.backgroundImage =
      `repeating-linear-gradient(0deg, rgba(255,255,255,0.045) 0px, rgba(255,255,255,0.045) 1px, rgba(0,0,0,0) 3px, rgba(0,0,0,0) 6px),
       repeating-linear-gradient(90deg, rgba(255,255,255,0.030) 0px, rgba(255,255,255,0.030) 1px, rgba(0,0,0,0) 3px, rgba(0,0,0,0) 6px)`;
    grain.style.animation = 'worldappGrain 7s linear infinite';
    host.appendChild(grain);
    this.grainEl = grain;

    const styleId = 'worldapp-mystic-style';
    if (!document.getElementById(styleId)) {
      const st = document.createElement('style');
      st.id = styleId;
      st.textContent = `
@keyframes worldappGrain {
  0% { transform: translateY(0px) translateX(0px); opacity: 0.10; }
  50% { transform: translateY(14px) translateX(-8px); opacity: 0.13; }
  100% { transform: translateY(0px) translateX(0px); opacity: 0.10; }
}`;
      document.head.appendChild(st);
    }

    const canvas = document.createElement('canvas');
    canvas.style.position = 'absolute';
    canvas.style.inset = '0';
    canvas.style.pointerEvents = 'none';
    canvas.style.zIndex = '4';
    canvas.style.opacity = '0.55';
    canvas.style.mixBlendMode = 'screen';
    host.appendChild(canvas);

    this.particleCanvas = canvas;
    this.particleCtx = canvas.getContext('2d', { alpha: true });

    this.resizeParticles();
  }

  private startOverlayLoop() {
    if (this.raf) cancelAnimationFrame(this.raf);

    const particles = this.makeParticles(220);
    let lastT = performance.now();

    const tick = (now: number) => {
      const dt = Math.min(33, now - lastT);
      lastT = now;

      this.animateAura(now * 0.001);
      this.drawParticles(particles, dt, now * 0.001);

      this.raf = requestAnimationFrame(tick);
    };

    this.raf = requestAnimationFrame(tick);
  }

  private animateAura(t: number) {
    if (!this.auraEl) return;

    const breath = 0.5 + 0.5 * Math.sin(t * 0.85);
    const selBoost = this.selectedId != null ? 1 : 0;

    const baseOpacity = 0.78 + 0.10 * breath + 0.08 * selBoost;
    const blur = 0.6 + 0.9 * breath + 0.7 * selBoost;

    this.auraEl.style.opacity = String(Math.min(0.98, Math.max(0.55, baseOpacity)));
    this.auraEl.style.filter = `blur(${blur}px)`;
  }

  private bumpAura(selected = false) {
    if (!this.auraEl) return;
    this.auraEl.style.opacity = selected ? '0.98' : '0.92';
    this.auraEl.style.filter = selected ? 'blur(1.8px)' : 'blur(1.2px)';
    setTimeout(() => {
      if (!this.auraEl) return;
      this.auraEl.style.opacity = '0.90';
    }, 220);
  }

  private resizeParticles() {
    if (!this.particleCanvas || !this.overlayHost) return;
    const rect = this.overlayHost.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);

    this.particleCanvas.width = Math.floor(rect.width * dpr);
    this.particleCanvas.height = Math.floor(rect.height * dpr);
  }

  private makeParticles(count: number) {
    const p: Array<{ x: number; y: number; r: number; vx: number; vy: number; a: number }> = [];
    const w = this.particleCanvas?.width ?? 1;
    const h = this.particleCanvas?.height ?? 1;

    for (let i = 0; i < count; i++) {
      p.push({
        x: Math.random() * w,
        y: Math.random() * h,
        r: 0.6 + Math.random() * 1.6,
        vx: -0.015 + Math.random() * 0.03,
        vy: -0.012 + Math.random() * 0.024,
        a: 0.10 + Math.random() * 0.22,
      });
    }
    return p;
  }

  private drawParticles(
    particles: Array<{ x: number; y: number; r: number; vx: number; vy: number; a: number }>,
    dtMs: number,
    t: number
  ) {
    if (!this.particleCanvas || !this.particleCtx) return;

    const ctx = this.particleCtx;
    const w = this.particleCanvas.width;
    const h = this.particleCanvas.height;

    ctx.clearRect(0, 0, w, h);

    const breath = 0.5 + 0.5 * Math.sin(t * 1.25);
    const selBoost = this.selectedId != null ? 0.10 : 0.0;

    for (const p of particles) {
      p.x += p.vx * dtMs;
      p.y += p.vy * dtMs;

      if (p.x < -10) p.x = w + 10;
      if (p.x > w + 10) p.x = -10;
      if (p.y < -10) p.y = h + 10;
      if (p.y > h + 10) p.y = -10;

      const alpha = p.a * (0.55 + 0.55 * breath) + selBoost;
      const rr = p.r * (0.85 + 0.25 * breath);

      ctx.beginPath();
      ctx.arc(p.x, p.y, rr, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(160, 220, 255, ${alpha.toFixed(3)})`;
      ctx.fill();
    }
  }

  // -----------------------------
  // Palette / continent logic
  // -----------------------------

  private fillForProps(p: any): string {
    const cont = this.getContinentFromProps(p);
    return (continentColors as any)[cont] || (continentColors as any)['Unknown'];
  }

  private getContinentFromProps(p: any): string {
    const c =
      p.CONTINENT ||
      p.continent ||
      p.REGION_UN ||
      p.REGION_WB ||
      p.SUBREGION ||
      p.region ||
      null;

    const s = String(c || '').trim();
    if (!s) return 'Unknown';
    if (s.includes('Africa')) return 'Africa';
    if (s.includes('Europe')) return 'Europe';
    if (s.includes('Asia')) return 'Asia';
    if (s.includes('Oceania') || s.includes('Australia')) return 'Oceania';
    if (s.includes('North America')) return 'North America';
    if (s.includes('South America')) return 'South America';
    if (s.includes('Antarctica')) return 'Antarctica';
    return s;
  }

  private altitudeToZoom(altitude: number): number {
    if (!Number.isFinite(altitude) || altitude <= 0) return 2.6;
    const z = 1.1 + 1.7 * (1 / altitude);
    return Math.max(1.2, Math.min(5.4, z));
  }

  private uniqueCountriesById(list: CountryModel[]): CountryModel[] {
    const m = new globalThis.Map<number, CountryModel>();
    for (const c of list) {
      if (c && Number.isFinite(c.id) && !m.has(c.id)) m.set(c.id, c);
    }
    return Array.from(m.values());
  }
}
