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

type MatrixNode = {
  x: number;
  y: number;
  homeX: number;
  homeY: number;
  vx: number;
  vy: number;
  links: number[];
  glow: number;
};

type MatrixPacket = {
  fromX: number;
  fromY: number;
  toIndex: number;
  progress: number;
  speed: number;
  alpha: number;
  label: string;
};

type MatrixRipple = {
  fromIndex: number;
  toIndex: number;
  delayMs: number;
  progress: number;
  speed: number;
  alpha: number;
};

type MatrixFieldRipple = {
  originX: number;
  originY: number;
  radius: number;
  speed: number;
  alpha: number;
  thickness: number;
};

type AmbientStar = {
  x: number;
  y: number;
  size: number;
  alpha: number;
};

@Injectable({ providedIn: 'root' })
export class GlobeService {
  private viewer: any = null;
  private Cesium: any = null;
  private overlayHost: HTMLElement | null = null;
  private particleCanvas: HTMLCanvasElement | null = null;
  private particleCtx: CanvasRenderingContext2D | null = null;
  private matrixBackdropImage: HTMLImageElement | null = null;
  private matrixBackdropReady = false;
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
  private readonly MATRIX_NODE_COUNT = 84;
  private readonly AMBIENT_STAR_COUNT = 140;
  private readonly MATRIX_LINK_DISTANCE = 150;
  private readonly MESSAGE_SPAWN_INTERVAL = 1200;
  private readonly MESSAGE_MAX = 18;
  private readonly FLOATING_WORD_COUNT = 42;
  private matrixNodes: MatrixNode[] = [];
  private ambientStars: AmbientStar[] = [];
  private messagePackets: MatrixPacket[] = [];
  private matrixRipples: MatrixRipple[] = [];
  private matrixFieldRipples: MatrixFieldRipple[] = [];
  private lastMessageSpawn = 0;
  private floatingWordPool: string[] = [];
  private fireworkWordGroups: string[][] = [];

  private labelsDataSource: any = null;
  private countriesDataSource: any = null;
  private renderingPaused = false;

  init(globeEl: HTMLElement): void {
    this.overlayHost = globeEl;
    if (getComputedStyle(globeEl).position === 'static') globeEl.style.position = 'relative';
    this.ensureMatrixBackdropImage();

    this.ensureCesium()
      .then((Cesium) => {
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
        viewer.scene.backgroundColor = Cesium.Color.BLACK;
        try { viewer.scene.skyBox.show = false; } catch {}
        const ocean = Cesium.Color.fromCssColorString('#0b2b3b');
        viewer.scene.globe.baseColor = ocean;
        viewer.scene.postProcessStages.fxaa.enabled = true;
        viewer.scene.screenSpaceCameraController.maximumZoomDistance = 60_000_000;
        viewer.scene.screenSpaceCameraController.minimumZoomDistance = 600_000;
        viewer.camera.setView({
          destination: Cesium.Cartesian3.fromDegrees(0, 20, 22_000_000),
        });

        this.viewer = viewer;
        const overlayTarget = viewer.scene.canvas?.parentElement ?? globeEl;
        this.overlayHost = overlayTarget;
        this.installOverlay(overlayTarget);
        this.startOverlayLoop();
        this.installClickHandler();
        this.readyResolver?.();

        if (this.cachedPayload) this.setDataFast(this.cachedPayload);
        if (this.cachedConnections.length) this.setConnections(this.cachedConnections);
      })
      .catch((err) => {
        console.warn('[globe] Cesium failed to load', err);
      });

    window.addEventListener('resize', () => this.resize());
  }

  resize(): void {
    if (this.renderingPaused) return;
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

  pauseRendering(): void {
    this.renderingPaused = true;
    if (this.raf) {
      cancelAnimationFrame(this.raf);
      this.raf = 0;
    }
    if (this.particleCanvas) {
      this.particleCanvas.style.display = 'none';
    }
    if (this.viewer) {
      try {
        this.viewer.useDefaultRenderLoop = false;
      } catch {}
    }
  }

  resumeRendering(): void {
    const wasPaused = this.renderingPaused;
    this.renderingPaused = false;
    if (this.particleCanvas) {
      this.particleCanvas.style.display = '';
    }
    if (this.viewer) {
      try {
        this.viewer.useDefaultRenderLoop = true;
        this.viewer.resize();
        this.viewer.scene?.requestRender?.();
      } catch {}
    }
    if (wasPaused) {
      this.resizeParticles();
      this.startOverlayLoop();
    }
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
          entity.polygon.material = new Cesium.ColorMaterialProperty(
            Cesium.Color.fromCssColorString(fill)
          );
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

  setFloatingWords(words: string[]): void {
    const cleaned = (words || [])
      .map((w) => String(w || '').trim())
      .filter((w) => w.length >= 3)
      .map((w) => w.slice(0, 24));
    const deduped = Array.from(new globalThis.Set(cleaned));
    this.floatingWordPool = deduped.slice(0, 160);
  }

  setFireworkWordGroups(groups: string[][]): void {
    const cleaned = (groups || [])
      .map((group) =>
        (group || [])
          .map((w) => String(w || '').trim())
          .filter((w) => w.length >= 2)
          .map((w) => w.slice(0, 24))
      )
      .filter((group) => group.length > 0);
    this.fireworkWordGroups = cleaned.slice(0, 160);
    if (!this.floatingWordPool.length && cleaned.length) {
      const flat = cleaned.flat();
      this.floatingWordPool = Array.from(new globalThis.Set(flat)).slice(0, 160);
    }
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
      destination: this.Cesium.Cartesian3.fromDegrees(0, 20, 22_000_000),
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
    this.seedMatrixNodes(this.particleCanvas.width, this.particleCanvas.height);
  }

  private startOverlayLoop() {
    if (this.raf) cancelAnimationFrame(this.raf);
    let lastT = performance.now();

    const tick = (now: number) => {
      const dt = Math.min(33, now - lastT);
      lastT = now;
      this.drawOverlay(dt, now);
      this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  }

  private drawOverlay(dtMs: number, nowMs: number) {
    if (this.renderingPaused) return;
    if (!this.particleCanvas || !this.particleCtx) return;
    const ctx = this.particleCtx;
    const w = this.particleCanvas.width;
    const h = this.particleCanvas.height;

    ctx.clearRect(0, 0, w, h);
    this.drawProjectiles(ctx, w, h, dtMs, nowMs);
  }

  private drawProjectiles(ctx: CanvasRenderingContext2D, w: number, h: number, dtMs: number, nowMs: number) {
    if (!this.viewer || !this.Cesium) return;

    const Cesium = this.Cesium;
    const occluder = new Cesium.EllipsoidalOccluder(
      this.viewer.scene.globe.ellipsoid,
      this.viewer.scene.camera.positionWC
    );
    const nodes = this.collectVisibleNodes(occluder, Cesium, w, h);

    this.drawMatrix(ctx, w, h, dtMs, nodes);
    if (!nodes.length) return;

    // Online users as blue dots.
    const dotRadius = Math.max(2.2, (this.particleScale || 1) * 1.6);
    ctx.fillStyle = 'rgba(80, 170, 255, 0.95)';
    for (const node of nodes) {
      ctx.beginPath();
      ctx.arc(node.x, node.y, dotRadius, 0, Math.PI * 2);
      ctx.fill();
    }

    this.drawGlobeConnections(ctx, nodes);
    this.spawnMessagePacket(nodes, nowMs);
    this.updateMessagePackets(ctx, dtMs);
  }

  private ensureMatrixBackdropImage(): void {
    if (this.matrixBackdropImage) return;
    const image = new Image();
    image.decoding = 'async';
    image.onload = () => {
      this.matrixBackdropReady = true;
    };
    image.src = '/assets/matrix-mesh.jpg?v=1';
    this.matrixBackdropImage = image;
  }

  private collectVisibleNodes(occluder: any, Cesium: any, w: number, h: number) {
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
    return nodes;
  }

  private drawMatrix(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
    dtMs: number,
    globeNodes: Array<{ x: number; y: number; id: string }>
  ): void {
    if (!this.matrixNodes.length) {
      this.seedMatrixNodes(w, h);
    }
    if (!this.matrixNodes.length) return;

    this.drawMatrixBackdrop(ctx, w, h);

    const drift = dtMs * 0.001;
    for (const node of this.matrixNodes) {
      node.x += node.vx * drift;
      node.y += node.vy * drift;
      node.vx += (node.homeX - node.x) * 0.00028;
      node.vy += (node.homeY - node.y) * 0.00028;
      node.vx *= 0.996;
      node.vy *= 0.996;
      node.glow = Math.max(0, node.glow - dtMs * 0.0007);
    }

    const fieldBoostByNode = this.updateMatrixFieldRipples(dtMs);

    for (const star of this.ambientStars) {
      ctx.fillStyle = `rgba(190, 220, 255, ${star.alpha})`;
      ctx.beginPath();
      ctx.arc(star.x, star.y, star.size * (this.particleScale || 1), 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.lineWidth = Math.max(1, (this.particleScale || 1) * 0.5);
    for (let i = 0; i < this.matrixNodes.length; i += 1) {
      const node = this.matrixNodes[i];
      for (const link of node.links) {
        if (link <= i || !this.matrixNodes[link]) continue;
        const other = this.matrixNodes[link];
        const glowBoost = Math.max(fieldBoostByNode[i] ?? 0, fieldBoostByNode[link] ?? 0);
        ctx.strokeStyle = `rgba(120, 180, 255, ${0.03 + glowBoost * 0.18})`;
        ctx.lineWidth = Math.max(0.55, (this.particleScale || 1) * (0.32 + glowBoost * 0.85));
        ctx.beginPath();
        ctx.moveTo(node.x, node.y);
        ctx.lineTo(other.x, other.y);
        ctx.stroke();
      }
    }

    for (let i = 0; i < this.matrixNodes.length; i += 1) {
      const node = this.matrixNodes[i];
      const fieldBoost = fieldBoostByNode[i] ?? 0;
      const radius = Math.max(1.15, (this.particleScale || 1) * (0.74 + node.glow * 0.55));
      ctx.fillStyle = `rgba(150, 205, 255, ${0.24 + node.glow * 0.18 + fieldBoost * 0.3})`;
      ctx.beginPath();
      ctx.arc(node.x, node.y, radius + fieldBoost * (this.particleScale || 1) * 0.45, 0, Math.PI * 2);
      ctx.fill();
    }

    this.updateMatrixRipples(ctx, dtMs);
  }

  private drawMatrixBackdrop(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    if (!this.matrixBackdropReady || !this.matrixBackdropImage) return;

    const { image, cx, cy, globeRx, globeRy, drawW, drawH, drawX, drawY } =
      this.getMatrixBackdropPlacement(w, h);

    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, w, h);
    ctx.ellipse(cx, cy, globeRx, globeRy, 0, 0, Math.PI * 2);
    ctx.clip('evenodd');
    ctx.globalAlpha = 0.32;
    ctx.drawImage(image, drawX, drawY, drawW, drawH);
    ctx.restore();

    ctx.save();
    const vignette = ctx.createRadialGradient(cx, cy, globeRx * 0.9, cx, cy, Math.max(w, h) * 0.78);
    vignette.addColorStop(0, 'rgba(0, 0, 0, 0)');
    vignette.addColorStop(1, 'rgba(0, 0, 0, 0.22)');
    ctx.fillStyle = vignette;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }

  private getMatrixBackdropPlacement(w: number, h: number) {
    const image = this.matrixBackdropImage!;
    const cx = w * 0.5;
    const cy = h * 0.52;
    const globeRx = w * 0.24;
    const globeRy = h * 0.255;
    const coverScale = Math.max(w / image.width, h / image.height) * 1.02;
    const drawW = image.width * coverScale;
    const drawH = image.height * coverScale;
    const drawX = (w - drawW) * 0.5;
    const drawY = (h - drawH) * 0.5;
    return { image, cx, cy, globeRx, globeRy, drawW, drawH, drawX, drawY };
  }

  private drawGlobeConnections(ctx: CanvasRenderingContext2D, globeNodes: Array<{ x: number; y: number; id: string }>): void {
    if (!globeNodes.length || !this.matrixNodes.length) return;
    const sample = globeNodes.slice(0, Math.min(18, globeNodes.length));
    ctx.lineWidth = Math.max(1, (this.particleScale || 1) * 0.45);
    for (const node of sample) {
      const targetIndex = this.findNearestMatrixNode(node.x, node.y);
      if (targetIndex < 0) continue;
      const target = this.matrixNodes[targetIndex];
      ctx.strokeStyle = 'rgba(95, 165, 255, 0.06)';
      ctx.beginPath();
      ctx.moveTo(node.x, node.y);
      ctx.lineTo(target.x, target.y);
      ctx.stroke();
    }
  }

  private spawnMessagePacket(nodes: Array<{ x: number; y: number }>, nowMs: number): void {
    if (!nodes.length || !this.matrixNodes.length) return;
    if (this.messagePackets.length >= this.MESSAGE_MAX) return;
    if (nowMs - this.lastMessageSpawn < this.MESSAGE_SPAWN_INTERVAL) return;

    const source = nodes[Math.floor(Math.random() * nodes.length)];
    const targetIndex = this.findNearestMatrixNode(source.x, source.y);
    if (targetIndex < 0) return;
    this.messagePackets.push({
      fromX: source.x,
      fromY: source.y,
      toIndex: targetIndex,
      progress: 0,
      speed: 0.00014 + Math.random() * 0.00008,
      alpha: 0.66,
      label: this.pickMessageLabel(),
    });
    this.lastMessageSpawn = nowMs;
  }

  private updateMessagePackets(ctx: CanvasRenderingContext2D, dtMs: number): void {
    if (!this.messagePackets.length || !this.matrixNodes.length) return;
    const alive: MatrixPacket[] = [];
    for (const packet of this.messagePackets) {
      const target = this.matrixNodes[packet.toIndex];
      if (!target) continue;
      packet.progress += packet.speed * dtMs;
      const t = Math.min(1, packet.progress);
      const eased = 1 - Math.pow(1 - t, 2.2);
      const x = packet.fromX + (target.x - packet.fromX) * eased;
      const y = packet.fromY + (target.y - packet.fromY) * eased;

      ctx.strokeStyle = `rgba(110, 190, 255, ${0.08 * (1 - t)})`;
      ctx.lineWidth = Math.max(0.7, (this.particleScale || 1) * 0.52);
      ctx.beginPath();
      ctx.moveTo(packet.fromX, packet.fromY);
      ctx.lineTo(x, y);
      ctx.stroke();

      ctx.fillStyle = `rgba(125, 205, 255, ${packet.alpha})`;
      ctx.beginPath();
      ctx.roundRect(
        x - 4 * (this.particleScale || 1),
        y - 2 * (this.particleScale || 1),
        8 * (this.particleScale || 1),
        4 * (this.particleScale || 1),
        3 * (this.particleScale || 1)
      );
      ctx.fill();

      if (packet.label && t > 0.14 && t < 0.92) {
        ctx.font = `${Math.max(9, 9 * (this.particleScale || 1))}px "Montserrat", sans-serif`;
        ctx.fillStyle = `rgba(190, 225, 255, ${0.62 * (1 - Math.abs(0.5 - t))})`;
        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillText(packet.label, x + 8 * (this.particleScale || 1), y);
      }

      if (t < 1) {
        alive.push(packet);
      } else {
        target.glow = Math.min(1, target.glow + 0.9);
        this.emitNodeRipple(packet.toIndex);
      }
    }
    this.messagePackets = alive;
  }

  private updateMatrixRipples(ctx: CanvasRenderingContext2D, dtMs: number): void {
    if (!this.matrixRipples.length || !this.matrixNodes.length) return;
    const alive: MatrixRipple[] = [];
    for (const ripple of this.matrixRipples) {
      if (ripple.delayMs > 0) {
        ripple.delayMs -= dtMs;
        alive.push(ripple);
        continue;
      }
      const from = this.matrixNodes[ripple.fromIndex];
      const to = this.matrixNodes[ripple.toIndex];
      if (!from || !to) continue;

      ripple.progress += ripple.speed * dtMs;
      const t = Math.min(1, ripple.progress);
      const x = from.x + (to.x - from.x) * t;
      const y = from.y + (to.y - from.y) * t;
      const tailT = Math.max(0, t - 0.18);
      const tailX = from.x + (to.x - from.x) * tailT;
      const tailY = from.y + (to.y - from.y) * tailT;

      ctx.strokeStyle = `rgba(145, 215, 255, ${0.34 * ripple.alpha * (1 - t * 0.45)})`;
      ctx.lineWidth = Math.max(0.95, (this.particleScale || 1) * 0.8);
      ctx.beginPath();
      ctx.moveTo(tailX, tailY);
      ctx.lineTo(x, y);
      ctx.stroke();

      ctx.fillStyle = `rgba(195, 236, 255, ${0.58 * ripple.alpha * (1 - t * 0.35)})`;
      ctx.beginPath();
      ctx.arc(x, y, Math.max(1.6, (this.particleScale || 1) * 1.3), 0, Math.PI * 2);
      ctx.fill();

      if (t < 1) {
        alive.push(ripple);
      } else {
        to.glow = Math.min(1, to.glow + 0.45);
      }
    }
    this.matrixRipples = alive;
  }

  private updateMatrixFieldRipples(dtMs: number): number[] {
    const boosts = new Array<number>(this.matrixNodes.length).fill(0);
    if (!this.matrixFieldRipples.length || !this.matrixNodes.length) return boosts;

    const alive: MatrixFieldRipple[] = [];
    for (const ripple of this.matrixFieldRipples) {
      ripple.radius += ripple.speed * dtMs;
      ripple.alpha *= 0.996;
      if (ripple.alpha < 0.02) continue;

      for (let i = 0; i < this.matrixNodes.length; i += 1) {
        const node = this.matrixNodes[i];
        const dx = node.x - ripple.originX;
        const dy = node.y - ripple.originY;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const delta = Math.abs(distance - ripple.radius);
        if (delta > ripple.thickness) continue;
        const intensity = (1 - delta / ripple.thickness) * ripple.alpha;
        boosts[i] = Math.max(boosts[i], intensity);
      }

      alive.push(ripple);
    }

    this.matrixFieldRipples = alive;
    return boosts;
  }

  private emitNodeRipple(nodeIndex: number): void {
    const node = this.matrixNodes[nodeIndex];
    if (!node) return;
    this.matrixFieldRipples.push({
      originX: node.x,
      originY: node.y,
      radius: 0,
      speed: 0.03 + Math.random() * 0.012,
      alpha: 0.42,
      thickness: Math.max(44, 32 * (this.particleScale || 1)),
    });

    const distances = new Array<number>(this.matrixNodes.length).fill(Number.POSITIVE_INFINITY);
    const queue: number[] = [nodeIndex];
    distances[nodeIndex] = 0;
    while (queue.length) {
      const current = queue.shift()!;
      const currentDistance = distances[current];
      for (const linked of this.matrixNodes[current]?.links ?? []) {
        if (!this.matrixNodes[linked]) continue;
        if (distances[linked] <= currentDistance + 1) continue;
        distances[linked] = currentDistance + 1;
        queue.push(linked);
      }
    }

    const seen = new globalThis.Set<string>();
    for (let i = 0; i < this.matrixNodes.length; i += 1) {
      for (const linked of this.matrixNodes[i]?.links ?? []) {
        const a = Math.min(i, linked);
        const b = Math.max(i, linked);
        const key = `${a}:${b}`;
        if (seen.has(key)) continue;
        seen.add(key);

        const da = distances[a];
        const db = distances[b];
        if (!Number.isFinite(da) || !Number.isFinite(db) || da === db) continue;

        const fromIndex = da < db ? a : b;
        const toIndex = da < db ? b : a;
        const depth = Math.min(da, db);
        this.matrixRipples.push({
          fromIndex,
          toIndex,
          delayMs: depth * 260,
          progress: 0,
          speed: 0.00018 + Math.random() * 0.00005,
          alpha: 0.36,
        });
      }
    }
  }

  private findNearestMatrixNode(x: number, y: number): number {
    let bestIndex = -1;
    let bestDistance = Number.POSITIVE_INFINITY;
    for (let i = 0; i < this.matrixNodes.length; i += 1) {
      const node = this.matrixNodes[i];
      const dx = node.x - x;
      const dy = node.y - y;
      const dist = dx * dx + dy * dy;
      if (dist < bestDistance) {
        bestDistance = dist;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  private findDirectionalMatrixNode(x: number, y: number): number {
    if (!this.matrixNodes.length || !this.particleCanvas) return -1;
    const cx = this.particleCanvas.width * 0.5;
    const cy = this.particleCanvas.height * 0.54;
    const sx = x - cx;
    const sy = y - cy;
    const sourceRadius = Math.sqrt(sx * sx + sy * sy);
    if (sourceRadius < 1) return this.findNearestMatrixNode(x, y);

    const dirX = sx / sourceRadius;
    const dirY = sy / sourceRadius;
    let bestIndex = -1;
    let bestScore = Number.POSITIVE_INFINITY;

    for (let i = 0; i < this.matrixNodes.length; i += 1) {
      const node = this.matrixNodes[i];
      const nx = node.x - cx;
      const ny = node.y - cy;
      const projection = nx * dirX + ny * dirY;
      if (projection <= sourceRadius + 18 * (this.particleScale || 1)) continue;
      const perpendicular = Math.abs(nx * dirY - ny * dirX);
      const radialDrift = Math.abs(Math.sqrt(nx * nx + ny * ny) - projection);
      const score = perpendicular + radialDrift * 0.35;
      if (score < bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestIndex >= 0 ? bestIndex : this.findNearestMatrixNode(x, y);
  }

  private seedMatrixNodes(w: number, h: number): void {
    if (!w || !h) return;
    if (!this.matrixBackdropReady || !this.matrixBackdropImage) {
      this.matrixNodes = [];
      return;
    }
    const next: MatrixNode[] = [];
    const { image, cx, cy, globeRx, globeRy, drawW, drawH, drawX, drawY } =
      this.getMatrixBackdropPlacement(w, h);
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = image.width;
    tempCanvas.height = image.height;
    const tempCtx = tempCanvas.getContext('2d', { willReadFrequently: true });
    if (!tempCtx) return;
    tempCtx.drawImage(image, 0, 0, image.width, image.height);
    const pixelData = tempCtx.getImageData(0, 0, image.width, image.height).data;

    const minGap = 18 * (this.particleScale || 1);
    const sampleStep = Math.max(8, Math.round(Math.min(w, h) / 110));
    const edgePad = Math.max(18, 16 * (this.particleScale || 1));
    const candidates: Array<{ x: number; y: number; score: number }> = [];

    const luminanceAt = (x: number, y: number): number => {
      const ix = Math.max(0, Math.min(image.width - 1, Math.floor(((x - drawX) / drawW) * image.width)));
      const iy = Math.max(0, Math.min(image.height - 1, Math.floor(((y - drawY) / drawH) * image.height)));
      const offset = (iy * image.width + ix) * 4;
      const r = pixelData[offset] ?? 0;
      const g = pixelData[offset + 1] ?? 0;
      const b = pixelData[offset + 2] ?? 0;
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };

    const insideCutout = (x: number, y: number) => {
      const dx = (x - cx) / globeRx;
      const dy = (y - cy) / globeRy;
      return dx * dx + dy * dy < 1.18 * 1.18;
    };

    for (let y = edgePad; y < h - edgePad; y += sampleStep) {
      for (let x = edgePad; x < w - edgePad; x += sampleStep) {
        if (insideCutout(x, y)) continue;
        const lum = luminanceAt(x, y);
        if (lum < 188) continue;
        const centerBias = Math.min(1, Math.hypot((x - cx) / w, (y - cy) / h) * 2.2);
        candidates.push({ x, y, score: lum + centerBias * 16 });
      }
    }

    candidates.sort((a, b) => b.score - a.score);
    for (const candidate of candidates) {
      if (next.length >= 118) break;
      let tooClose = false;
      for (const existing of next) {
        const dx = existing.x - candidate.x;
        const dy = existing.y - candidate.y;
        if (dx * dx + dy * dy < minGap * minGap) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;
      next.push({
        x: candidate.x,
        y: candidate.y,
        homeX: candidate.x,
        homeY: candidate.y,
        vx: (Math.random() - 0.5) * 0.002,
        vy: (Math.random() - 0.5) * 0.002,
        links: [],
        glow: Math.random() * 0.05,
      });
    }

    const addLink = (a: number, b: number) => {
      if (a === b || !next[a] || !next[b]) return;
      if (!next[a].links.includes(b)) next[a].links.push(b);
      if (!next[b].links.includes(a)) next[b].links.push(a);
    };

    for (let i = 0; i < next.length; i += 1) {
      const distances: Array<{ index: number; dist: number }> = [];
      for (let j = 0; j < next.length; j += 1) {
        if (i === j) continue;
        const dx = next[j].x - next[i].x;
        const dy = next[j].y - next[i].y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist > 96 * (this.particleScale || 1)) continue;
        distances.push({ index: j, dist });
      }
      distances.sort((a, b) => a.dist - b.dist);
      for (const target of distances.slice(0, 4)) {
        addLink(i, target.index);
      }
    }

    this.matrixNodes = next;
    this.ambientStars = [];
    this.messagePackets = [];
    this.matrixRipples = [];
    this.matrixFieldRipples = [];
  }

  private pickFireworkWord(): string {
    if (this.floatingWordPool.length) {
      return this.floatingWordPool[Math.floor(Math.random() * this.floatingWordPool.length)];
    }
    return '';
  }

  private pickMessageLabel(): string {
    const group = this.pickFireworkGroup();
    if (group.length) return group.slice(0, 2).join(' ');
    return '';
  }

  private pickFireworkGroup(): string[] {
    if (this.fireworkWordGroups.length) {
      return this.fireworkWordGroups[Math.floor(Math.random() * this.fireworkWordGroups.length)];
    }
    if (!this.floatingWordPool.length) return [];
    const count = Math.min(8, Math.max(2, Math.floor(3 + Math.random() * 4)));
    const group: string[] = [];
    for (let i = 0; i < count; i += 1) {
      group.push(this.pickFireworkWord());
    }
    return group.filter(Boolean);
  }

  private drawFloatingWords(ctx: CanvasRenderingContext2D, w: number, h: number, dtMs: number): void {
    return;
  }

  private seedFloatingWords(w: number, h: number): void {
    return;
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
