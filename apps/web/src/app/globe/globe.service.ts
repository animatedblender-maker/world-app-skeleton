import { Injectable } from '@angular/core';
import type { CountryModel } from '../data/countries.service';

type CountriesPayload = { features: any[]; countries: CountryModel[] };

/** Connection point model (floating dots / stars). */
export type ConnectionPoint = {
  id: string | number;
  lat: number;
  lng: number;
  cc?: string | null;
  color?: string;
  radius?: number;
};

@Injectable({ providedIn: 'root' })
export class GlobeService {
  private viewer: any = null;
  private Cesium: any = null;
  private overlayHost: HTMLElement | null = null;
  private particleCanvas: HTMLCanvasElement | null = null;
  private particleCtx: CanvasRenderingContext2D | null = null;
  private raf = 0;
  private particleScale = 1;
  private canvasOffsetX = 0;
  private canvasOffsetY = 0;
  private canvasCssWidth = 0;
  private canvasCssHeight = 0;
  private drawBufferWidth = 0;
  private drawBufferHeight = 0;
  private cssScaleX = 1;
  private cssScaleY = 1;
  private hostCssWidth = 0;
  private hostCssHeight = 0;
  private readyResolver: (() => void) | null = null;
  private readyPromise = new Promise<void>((resolve) => {
    this.readyResolver = resolve;
  });

  private countries: CountryModel[] = [];
  private cachedPayload: CountriesPayload | null = null;
  private countryClickCb: ((country: CountryModel) => void) | null = null;
  private selectedId: number | null = null;

  private cachedConnections: ConnectionPoint[] = [];
  private onlineConnectionIds = new globalThis.Set<string>();

  private readonly MAX_NETWORK_NODES = 140;
  private readonly MAX_NETWORK_LINKS = 2;
  private readonly MAX_LINK_DISTANCE = 160;
  private readonly FIRE_TRAIL_ALPHA = 0.55;
  private readonly FIRE_MAX_SEGMENTS = 4;
  private readonly FIRE_MIN_SPEED = 0.18;
  private readonly FIRE_MAX_SPEED = 0.35;
  private fireTrails = new globalThis.Map<
    string,
    { phase: number; speed: number; tail: Array<{ x: number; y: number }> }
  >();

  private labelsDataSource: any = null;
  private countriesDataSource: any = null;

  init(globeEl: HTMLElement): void {
    this.overlayHost = globeEl;
    if (getComputedStyle(globeEl).position === 'static') globeEl.style.position = 'relative';

    this.ensureCesium().then((Cesium) => {
      if (!Cesium) return;
      this.Cesium = Cesium;

      const blankPixel =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
      const viewer = new Cesium.Viewer(globeEl, {
        animation: false,
        timeline: false,
        geocoder: false,
        homeButton: false,
        baseLayerPicker: false,
        imageryProvider: new Cesium.SingleTileImageryProvider({ url: blankPixel }),
        terrainProvider: new Cesium.EllipsoidTerrainProvider(),
        sceneModePicker: false,
        navigationHelpButton: false,
        infoBox: false,
        selectionIndicator: false,
        fullscreenButton: false,
        shouldAnimate: true,
      });

      // Hide Cesium credits/logo.
      try { viewer.cesiumWidget.creditContainer.style.display = 'none'; } catch {}

      // Stylized globe (no photo imagery).
      viewer.imageryLayers.removeAll();

      viewer.scene.globe.enableLighting = false;
      viewer.scene.skyAtmosphere.show = false;
      viewer.scene.globe.showGroundAtmosphere = false;
      viewer.scene.backgroundColor = Cesium.Color.fromCssColorString('#05080f');
      const ocean = Cesium.Color.fromCssColorString('#0b2b3b');
      viewer.scene.globe.baseColor = ocean;
      viewer.scene.globe.material = Cesium.Material.fromType('Color', { color: ocean });
      viewer.scene.postProcessStages.fxaa.enabled = true;
      viewer.scene.screenSpaceCameraController.maximumZoomDistance = 60_000_000;
      viewer.scene.screenSpaceCameraController.minimumZoomDistance = 600_000;

      this.viewer = viewer;
      const overlayTarget = viewer.scene.canvas?.parentElement ?? globeEl;
      this.overlayHost = overlayTarget;
      this.installOverlay(overlayTarget);
      this.startOverlayLoop();
      this.installClickHandler();
      this.readyResolver?.();

      if (this.cachedPayload) this.setDataFast(this.cachedPayload);
      if (this.cachedConnections.length) this.setConnections(this.cachedConnections);
    });

    window.addEventListener('resize', () => this.resize());
  }

  resize(): void {
    if (this.viewer) {
      try { this.viewer.resize(); } catch {}
    }
    this.resizeParticles();
  }

  onCountryClick(cb: (country: CountryModel) => void) {
    this.countryClickCb = cb;
  }

  whenReady(): Promise<void> {
    return this.readyPromise;
  }

  setInteractive(enabled: boolean): void {
    if (!this.viewer) return;
    const ctrl = this.viewer.scene.screenSpaceCameraController;
    ctrl.enableRotate = enabled;
    ctrl.enableZoom = enabled;
    ctrl.enableTranslate = enabled;
    ctrl.enableTilt = enabled;
    ctrl.enableLook = enabled;
  }

  setData(payload: CountriesPayload): void {
    this.setDataFast(payload);
  }

  restoreCachedDataIfAny(): void {
    if (this.cachedPayload) this.setDataFast(this.cachedPayload);
  }

  setDataFast(payload: CountriesPayload): void {
    this.cachedPayload = payload;
    this.countries = payload.countries || [];
    if (!this.viewer || !this.Cesium) return;

    const Cesium = this.Cesium;
    if (this.countriesDataSource) {
      try { this.viewer.dataSources.remove(this.countriesDataSource, true); } catch {}
    }
    if (this.labelsDataSource) {
      try { this.viewer.dataSources.remove(this.labelsDataSource, true); } catch {}
    }

    const features = (payload.features || []).map((f) => {
      const props = (f.properties ??= {});
      const rawId = f.__id ?? props.__id ?? props.id;
      const id = Number(rawId);
      props.__id = Number.isFinite(id) ? id : undefined;
      return f;
    });
    const featureCollection = { type: 'FeatureCollection', features };
    const ds = new Cesium.GeoJsonDataSource('countries');
    ds.load(featureCollection as any, { clampToGround: true }).then((loaded: any) => {
      for (const entity of loaded.entities.values) {
        const id = entity.properties?.__id?.getValue?.();
        const fill = this.countryFillColor(Number(id));
        if (entity.polygon) {
          entity.polygon.material = Cesium.Color.fromCssColorString(fill);
          entity.polygon.outline = true;
          entity.polygon.outlineColor = Cesium.Color.fromCssColorString('rgba(8,22,40,0.65)');
          entity.polygon.outlineWidth = 1.1 as any;
        }
      }
      this.countriesDataSource = loaded;
      this.viewer.dataSources.add(loaded);

      const nameById = new Map<number, string>();
      const labelSizeById = new Map<number, number>();
      for (const c of this.countries) {
        if (Number.isFinite(c.id as any)) {
          const cid = Number(c.id);
          nameById.set(cid, c.name);
          labelSizeById.set(cid, Number.isFinite(c.labelSize as any) ? Number(c.labelSize) : 1);
        }
      }
      const labels = new Cesium.CustomDataSource('country-labels');
      const now = Cesium.JulianDate.now();
      for (const entity of loaded.entities.values) {
        const id = Number(entity.properties?.__id?.getValue?.());
        const fallbackName = entity.properties?.name?.getValue?.() || entity.properties?.NAME?.getValue?.();
        const name = nameById.get(id) || fallbackName;
        if (!name) continue;
        const labelSize = labelSizeById.get(id) ?? 1;
        const labelXRaw =
          [
            entity.properties?.LABEL_X?.getValue?.(now),
            entity.properties?.label_x?.getValue?.(now),
            entity.properties?.LABEL_X?.getValue?.(),
            entity.properties?.label_x?.getValue?.(),
          ].find((v) => Number.isFinite(Number(v))) ?? null;
        const labelYRaw =
          [
            entity.properties?.LABEL_Y?.getValue?.(now),
            entity.properties?.label_y?.getValue?.(now),
            entity.properties?.LABEL_Y?.getValue?.(),
            entity.properties?.label_y?.getValue?.(),
          ].find((v) => Number.isFinite(Number(v))) ?? null;
        const labelX = labelXRaw == null ? NaN : Number(labelXRaw);
        const labelY = labelYRaw == null ? NaN : Number(labelYRaw);

        let position: any = null;
        if (Number.isFinite(labelX) && Number.isFinite(labelY)) {
          position = Cesium.Cartesian3.fromDegrees(labelX, labelY);
        } else {
          const hierarchy = entity.polygon?.hierarchy?.getValue?.(now);
          const positions = hierarchy?.positions;
          if (!positions || !positions.length) continue;
          const sphere = Cesium.BoundingSphere.fromPoints(positions);
          position = sphere.center;
        }

        if (!position) continue;
        const maxDistance =
          labelSize <= 0.5 ? 700_000 :
          labelSize <= 0.8 ? 1_400_000 :
          labelSize <= 1.2 ? 2_600_000 :
          labelSize <= 1.8 ? 4_500_000 :
          8_000_000;
        const fontSize =
          labelSize <= 0.5 ? 11 :
          labelSize <= 0.8 ? 12 :
          labelSize <= 1.2 ? 14 :
          labelSize <= 1.8 ? 16 :
          18;
        labels.entities.add({
          position,
          label: {
            text: name,
            font: `${fontSize}px "Montserrat", sans-serif`,
            fillColor: Cesium.Color.fromCssColorString('rgba(252,246,228,0.98)'),
            outlineColor: Cesium.Color.fromCssColorString('rgba(8,16,24,0.92)'),
            outlineWidth: 4,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            showBackground: true,
            backgroundColor: Cesium.Color.fromCssColorString('rgba(6,14,24,0.45)'),
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            distanceDisplayCondition: new Cesium.DistanceDisplayCondition(0, maxDistance),
            scaleByDistance: new Cesium.NearFarScalar(400_000, 1.0, maxDistance, 0.35),
            translucencyByDistance: new Cesium.NearFarScalar(400_000, 1.0, maxDistance, 0.0),
          },
        });
      }
      this.labelsDataSource = labels;
      this.viewer.dataSources.add(labels);
    });

    // Labels enabled for country names.
  }

  setConnections(points: ConnectionPoint[]): void {
    this.cachedConnections = points || [];
  }

  setConnectionOnline(id: string | number, online: boolean): void {
    const key = String(id);
    if (online) this.onlineConnectionIds.add(key);
    else this.onlineConnectionIds.delete(key);
  }

  setConnectionsOnline(idsOnline: Array<string | number>): void {
    this.onlineConnectionIds = new globalThis.Set<string>((idsOnline || []).map((x) => String(x)));
  }

  setConnectionsCountryFilter(_iso2: string | null): void {}
  showAllLabels(): void {}
  showFocusLabel(_countryId: number): void {}
  setSoloCountry(_countryId: number | null): void {}

  selectCountry(countryId: number | null): void {
    this.selectedId = countryId;
  }

  setViewPadding(_padding: any): void {}
  resetViewPadding(): void {}

  flyTo(lat: number, lng: number, altitudeOrZoom: number, ms = 900): void {
    if (!this.viewer || !this.Cesium) return;
    const height = this.altitudeToHeight(altitudeOrZoom);
    this.viewer.camera.flyTo({
      destination: this.Cesium.Cartesian3.fromDegrees(lng, lat, height),
      duration: ms / 1000,
    });
  }

  resetView(): void {
    if (!this.viewer || !this.Cesium) return;
    this.viewer.camera.flyTo({
      destination: this.Cesium.Cartesian3.fromDegrees(0, 20, 12_000_000),
      duration: 0.9,
    });
  }

  // -----------------------------
  // Overlay: stars + projectiles
  // -----------------------------

  private installOverlay(host: HTMLElement) {
    if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
    const canvas = document.createElement('canvas');
    canvas.style.position = 'absolute';
    canvas.style.inset = '0';
    canvas.style.pointerEvents = 'none';
    canvas.style.zIndex = '4';
    canvas.style.opacity = '1';
    canvas.style.mixBlendMode = 'normal';
    host.appendChild(canvas);
    this.particleCanvas = canvas;
    this.particleCtx = canvas.getContext('2d', { alpha: true });
    this.resizeParticles();
  }

  private resizeParticles() {
    if (!this.particleCanvas || !this.overlayHost) return;
    const canvasEl = this.viewer?.scene?.canvas;
    const canvasRect = canvasEl?.getBoundingClientRect?.() ?? this.overlayHost.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.particleScale = dpr;
    this.canvasOffsetX = 0;
    this.canvasOffsetY = 0;
    this.hostCssWidth = canvasRect.width;
    this.hostCssHeight = canvasRect.height;
    this.canvasCssWidth = canvasRect.width;
    this.canvasCssHeight = canvasRect.height;
    const drawW = this.viewer?.scene?.drawingBufferWidth ?? canvasEl?.width ?? canvasRect.width;
    const drawH = this.viewer?.scene?.drawingBufferHeight ?? canvasEl?.height ?? canvasRect.height;
    this.drawBufferWidth = drawW || canvasRect.width || 1;
    this.drawBufferHeight = drawH || canvasRect.height || 1;
    this.cssScaleX = this.canvasCssWidth ? this.canvasCssWidth / this.drawBufferWidth : 1;
    this.cssScaleY = this.canvasCssHeight ? this.canvasCssHeight / this.drawBufferHeight : 1;
    this.particleCanvas.width = Math.floor(canvasRect.width * dpr);
    this.particleCanvas.height = Math.floor(canvasRect.height * dpr);
  }

  private startOverlayLoop() {
    if (this.raf) cancelAnimationFrame(this.raf);
    let lastT = performance.now();

    const tick = (now: number) => {
      const dt = Math.min(33, now - lastT);
      lastT = now;
      this.drawOverlay(dt, now * 0.001);
      this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  }

  private drawOverlay(_dtMs: number, t: number) {
    if (!this.particleCanvas || !this.particleCtx) return;
    const ctx = this.particleCtx;
    const w = this.particleCanvas.width;
    const h = this.particleCanvas.height;

    ctx.clearRect(0, 0, w, h);

    this.drawProjectiles(ctx, w, h, t);
  }

  private drawProjectiles(ctx: CanvasRenderingContext2D, w: number, h: number, t: number) {
    if (!this.viewer || !this.Cesium) return;

    const Cesium = this.Cesium;
    const occluder = new Cesium.EllipsoidalOccluder(
      this.viewer.scene.globe.ellipsoid,
      this.viewer.scene.camera.positionWC
    );
    const nodes: Array<{ x: number; y: number; id: string }> = [];
    const scale = this.particleScale || 1;
    const cssW = this.hostCssWidth || w / scale;
    const cssH = this.hostCssHeight || h / scale;
    for (const p of this.cachedConnections) {
      if (nodes.length >= this.MAX_NETWORK_NODES) break;
      if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng)) continue;
      if (this.onlineConnectionIds.size > 0 && !this.onlineConnectionIds.has(String(p.id))) continue;
      const cart = Cesium.Cartesian3.fromDegrees(p.lng, p.lat);
      if (!occluder.isPointVisible(cart)) continue;
      const screen = this.viewer.scene.cartesianToCanvasCoordinates(cart);
      if (!screen) continue;
      const cssX = screen.x * this.cssScaleX;
      const cssY = screen.y * this.cssScaleY;
      const sx = cssX + this.canvasOffsetX;
      const sy = cssY + this.canvasOffsetY;
      if (sx < -20 || sy < -20 || sx > cssW + 20 || sy > cssH + 20) continue;
      nodes.push({ x: sx * scale, y: sy * scale, id: String(p.id) });
    }

    if (nodes.length < 2) return;

    // Stars (online users)
    ctx.fillStyle = 'rgba(90, 175, 255, 1)';
    ctx.strokeStyle = 'rgba(5, 20, 45, 0.8)';
    ctx.lineWidth = 0.6;
    for (const node of nodes) {
      const size = 5.8;
      this.drawStar(ctx, node.x, node.y, size, size * 0.45, 5, true);
    }

    // Build nearest links and animate projectiles.
    const links: Array<{ a: number; b: number; d: number }> = [];
    const maxDistSq = this.MAX_LINK_DISTANCE * this.MAX_LINK_DISTANCE;
    for (let i = 0; i < nodes.length; i += 1) {
      const a = nodes[i];
      const nearest: Array<{ idx: number; d: number }> = [];
      for (let j = 0; j < nodes.length; j += 1) {
        if (i === j) continue;
        const b = nodes[j];
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        const d = dx * dx + dy * dy;
        if (d > maxDistSq) continue;
        nearest.push({ idx: j, d });
      }
      nearest.sort((n1, n2) => n1.d - n2.d);
      for (let k = 0; k < Math.min(this.MAX_NETWORK_LINKS, nearest.length); k += 1) {
        const idx = nearest[k].idx;
        if (i < idx) links.push({ a: i, b: idx, d: nearest[k].d });
      }
    }

    for (let i = 0; i < links.length; i += 1) {
      const link = links[i];
      const p1 = nodes[link.a];
      const p2 = nodes[link.b];
      const key = `${link.a}-${link.b}`;
      const state =
        this.fireTrails.get(key) ??
        { phase: Math.random(), speed: this.FIRE_MIN_SPEED + Math.random() * (this.FIRE_MAX_SPEED - this.FIRE_MIN_SPEED), tail: [] };
      state.phase = (state.phase + state.speed * 0.016) % 1;
      this.fireTrails.set(key, state);

      const phase = state.phase;
      const x = p1.x + (p2.x - p1.x) * phase;
      const y = p1.y + (p2.y - p1.y) * phase;
      if (state.tail.length) state.tail.length = 0;

      const sparkle = 2.2;
      ctx.fillStyle = 'rgba(140, 200, 255, 0.95)';
      ctx.beginPath();
      ctx.arc(x, y, sparkle, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  private drawStar(
    ctx: CanvasRenderingContext2D,
    cx: number,
    cy: number,
    outerR: number,
    innerR: number,
    points: number,
    stroke = false
  ) {
    const step = Math.PI / points;
    let rot = Math.PI / 2 * 3;
    ctx.beginPath();
    for (let i = 0; i < points; i += 1) {
      const x1 = cx + Math.cos(rot) * outerR;
      const y1 = cy + Math.sin(rot) * outerR;
      ctx.lineTo(x1, y1);
      rot += step;
      const x2 = cx + Math.cos(rot) * innerR;
      const y2 = cy + Math.sin(rot) * innerR;
      ctx.lineTo(x2, y2);
      rot += step;
    }
    ctx.lineTo(cx, cy - outerR);
    ctx.closePath();
    ctx.fill();
    if (stroke) ctx.stroke();
  }

  // -----------------------------
  // Helpers
  // -----------------------------

  private altitudeToHeight(altitude: number): number {
    if (!Number.isFinite(altitude) || altitude <= 0) return 8_000_000;
    return Math.max(900_000, Math.min(40_000_000, 8_000_000 / altitude));
  }

  private countryFillColor(id: number): string {
    const palette = [
      '#7E9E5B', // sage
      '#A7BFA5', // soft green
      '#C8B87A', // sand
      '#D1A76C', // ochre
      '#7FA3B8', // slate blue
      '#5F8E8E', // muted teal
      '#B48B6A', // clay
      '#8C9C8C', // olive grey
    ];
    const idx = Number.isFinite(id) ? Math.abs(id) % palette.length : 0;
    return palette[idx];
  }

  private installClickHandler(): void {
    if (!this.viewer || !this.Cesium) return;
    const Cesium = this.Cesium;
    const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas);
    handler.setInputAction((movement: any) => {
      const picked = this.viewer.scene.pick(movement.position);
      const id = picked?.id?.properties?.__id?.getValue?.() ?? picked?.id?.properties?.__id;
      const num = Number(id);
      if (!Number.isFinite(num)) return;
      const found = this.countries.find((c) => c.id === num);
      if (!found) return;
      this.selectCountry(found.id);
      if (this.countryClickCb) this.countryClickCb(found);
      else this.flyTo(found.center.lat, found.center.lng, found.flyAltitude ?? 1.0, 900);
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK);
  }

  private ensureCesium(): Promise<any> {
    const w = window as any;
    if (w.Cesium) return Promise.resolve(w.Cesium);
    return new Promise((resolve, reject) => {
      w.CESIUM_BASE_URL = 'https://unpkg.com/cesium@1.116.0/Build/Cesium/';
      const linkId = 'cesium-widgets-css';
      if (!document.getElementById(linkId)) {
        const link = document.createElement('link');
        link.id = linkId;
        link.rel = 'stylesheet';
        link.href = 'https://unpkg.com/cesium@1.116.0/Build/Cesium/Widgets/widgets.css';
        document.head.appendChild(link);
      }
      const scriptId = 'cesium-lib';
      if (document.getElementById(scriptId)) {
        const ready = (window as any).Cesium;
        if (ready) resolve(ready);
        return;
      }
      const script = document.createElement('script');
      script.id = scriptId;
      script.src = 'https://unpkg.com/cesium@1.116.0/Build/Cesium/Cesium.js';
      script.async = true;
      script.onload = () => resolve((window as any).Cesium);
      script.onerror = () => reject(new Error('Failed to load Cesium'));
      document.head.appendChild(script);
    });
  }
}
