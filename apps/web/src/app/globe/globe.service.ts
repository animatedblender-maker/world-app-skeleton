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

type FireworkWord = {
  text: string;
  x: number;
  y: number;
  life: number;
  ttl: number;
  size: number;
  vx: number;
  vy: number;
};

type FireworkShot = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  explodeAt: number;
  trail: Array<{ x: number; y: number }>;
  burstWords: FireworkWord[] | null;
};

type FireworkParticle = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  ttl: number;
  size: number;
};

type FloatingWord = {
  text: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  alpha: number;
  size: number;
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
  private readonly FIREWORK_SPAWN_INTERVAL = 680;
  private readonly FIREWORK_MIN_SPEED = 0.03;
  private readonly FIREWORK_MAX_SPEED = 0.055;
  private readonly FIREWORK_MIN_TIME = 1600;
  private readonly FIREWORK_MAX_TIME = 2800;
  private readonly FIREWORK_MAX = 18;
  private readonly FIREWORK_TRAIL = 10;
  private readonly FLOATING_WORD_COUNT = 42;
  private fireworkShots: FireworkShot[] = [];
  private fireworkParticles: FireworkParticle[] = [];
  private lastFireworkSpawn = 0;
  private floatingWords: FloatingWord[] = [];
  private floatingWordPool: string[] = [];
  private fireworkWordGroups: string[][] = [];

  private labelsDataSource: any = null;
  private countriesDataSource: any = null;

  init(globeEl: HTMLElement): void {
    this.overlayHost = globeEl;
    if (getComputedStyle(globeEl).position === 'static') globeEl.style.position = 'relative';

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
    this.floatingWords = [];
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

    if (!nodes.length) return;

    // Online users as blue dots.
    const dotRadius = Math.max(2.2, (this.particleScale || 1) * 1.6);
    ctx.fillStyle = 'rgba(80, 170, 255, 0.95)';
    for (const node of nodes) {
      ctx.beginPath();
      ctx.arc(node.x, node.y, dotRadius, 0, Math.PI * 2);
      ctx.fill();
    }

    this.spawnFirework(nodes, w, h, nowMs);
    this.updateFireworks(ctx, w, h, dtMs);
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

  private spawnFirework(nodes: Array<{ x: number; y: number }>, w: number, h: number, nowMs: number): void {
    if (!nodes.length) return;
    if (this.fireworkShots.length >= this.FIREWORK_MAX) return;
    if (nowMs - this.lastFireworkSpawn < this.FIREWORK_SPAWN_INTERVAL) return;

    const node = nodes[Math.floor(Math.random() * nodes.length)];
    const cx = w * 0.5;
    const cy = h * 0.5;
    const dx = node.x - cx;
    const dy = node.y - cy;
    const baseAngle = Math.atan2(dy, dx);
    const jitter = (Math.random() - 0.5) * 0.55;
    const angle = baseAngle + jitter;
    const speed = this.FIREWORK_MIN_SPEED + Math.random() * (this.FIREWORK_MAX_SPEED - this.FIREWORK_MIN_SPEED);
    const shot: FireworkShot = {
      x: node.x,
      y: node.y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      life: 0,
      explodeAt:
        this.FIREWORK_MIN_TIME +
        Math.random() * (this.FIREWORK_MAX_TIME - this.FIREWORK_MIN_TIME),
      trail: [],
      burstWords: null,
    };
    this.fireworkShots.push(shot);
    this.lastFireworkSpawn = nowMs;
  }

  private updateFireworks(ctx: CanvasRenderingContext2D, w: number, h: number, dtMs: number): void {
    if (!this.fireworkShots.length && !this.fireworkParticles.length) return;
    const trailColor = 'rgba(255,255,255,0.45)';
    const headColor = 'rgba(255,255,255,0.85)';
    const lineWidth = Math.max(1, (this.particleScale || 1) * 0.7);

    ctx.lineWidth = lineWidth;
    const updated: FireworkShot[] = [];

    for (const shot of this.fireworkShots) {
      if (!shot.burstWords) {
        shot.life += dtMs;
        shot.x += shot.vx * dtMs;
        shot.y += shot.vy * dtMs;
        shot.trail.push({ x: shot.x, y: shot.y });
        if (shot.trail.length > this.FIREWORK_TRAIL) shot.trail.shift();

        ctx.strokeStyle = trailColor;
        ctx.beginPath();
        for (let i = 0; i < shot.trail.length; i += 1) {
          const p = shot.trail[i];
          if (i === 0) ctx.moveTo(p.x, p.y);
          else ctx.lineTo(p.x, p.y);
        }
        ctx.stroke();

        ctx.fillStyle = headColor;
        ctx.beginPath();
        ctx.arc(shot.x, shot.y, Math.max(1.6, (this.particleScale || 1) * 0.9), 0, Math.PI * 2);
        ctx.fill();

        if (shot.life >= shot.explodeAt) {
          const group = this.pickFireworkGroup();
          const words = group.length ? group : [];
          const shuffled = [...words].sort(() => Math.random() - 0.5);
          const count = Math.min(8, shuffled.length);
          const burst: FireworkWord[] = [];
          if (count > 0) {
            const baseAngle = Math.atan2(shot.vy, shot.vx);
            const spread = Math.PI / 4;
            const step = count > 1 ? (spread * 2) / (count - 1) : 0;
            for (let i = 0; i < count; i += 1) {
              const offset = count > 1 ? -spread + step * i : 0;
              const angle = baseAngle + offset + (Math.random() - 0.5) * 0.1;
              const spd = 0.04 + Math.random() * 0.1;
              burst.push({
                text: shuffled[i],
                x: shot.x,
                y: shot.y,
                life: 0,
                ttl: 1300 + Math.random() * 700,
                size: 12 + Math.random() * 8,
                vx: Math.cos(angle) * spd,
                vy: Math.sin(angle) * spd,
              });
            }
            shot.burstWords = burst;
          }
        }
      }

      if (shot.burstWords) {
        const alive: FireworkWord[] = [];
        for (const word of shot.burstWords) {
          word.life += dtMs;
          word.x += word.vx * dtMs;
          word.y += word.vy * dtMs;
          const progress = Math.min(1, word.life / word.ttl);
          const alpha = 1 - progress;
          const size = word.size + progress * 6;
          ctx.font = `${size}px "Montserrat", sans-serif`;
          ctx.fillStyle = `rgba(255,255,255,${0.75 * alpha})`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText(word.text, word.x, word.y);
          if (word.life < word.ttl) {
            alive.push(word);
          } else {
            const angle = Math.atan2(word.vy, word.vx);
            const count = 8 + Math.floor(Math.random() * 8);
            for (let i = 0; i < count; i += 1) {
              const jitter = (Math.random() - 0.5) * Math.PI * 0.6;
              const spd = 0.03 + Math.random() * 0.08;
              this.fireworkParticles.push({
                x: word.x,
                y: word.y,
                vx: Math.cos(angle + jitter) * spd,
                vy: Math.sin(angle + jitter) * spd,
                life: 0,
                ttl: 650 + Math.random() * 650,
                size: 1.2 + Math.random() * 1.8,
              });
            }
          }
        }
        if (alive.length) {
          shot.burstWords = alive;
          updated.push(shot);
        }
      } else if (shot.life < shot.explodeAt) {
        updated.push(shot);
      }
    }

    this.fireworkShots = updated;

    if (this.fireworkParticles.length) {
      const nextParticles: FireworkParticle[] = [];
      for (const particle of this.fireworkParticles) {
        particle.life += dtMs;
        particle.x += particle.vx * dtMs;
        particle.y += particle.vy * dtMs;
        const progress = Math.min(1, particle.life / particle.ttl);
        const alpha = 1 - progress;
        ctx.fillStyle = `rgba(255,255,255,${0.7 * alpha})`;
        ctx.beginPath();
        ctx.arc(particle.x, particle.y, particle.size, 0, Math.PI * 2);
        ctx.fill();
        if (particle.life < particle.ttl) nextParticles.push(particle);
      }
      this.fireworkParticles = nextParticles;
    }
  }

  private pickFireworkWord(): string {
    if (this.floatingWordPool.length) {
      return this.floatingWordPool[Math.floor(Math.random() * this.floatingWordPool.length)];
    }
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
    const pool = this.floatingWordPool;
    if (!pool.length) {
      this.floatingWords = [];
      return;
    }

    const count = Math.min(this.FLOATING_WORD_COUNT, pool.length);
    this.floatingWords = [];
    for (let i = 0; i < count; i += 1) {
      const text = pool[Math.floor(Math.random() * pool.length)];
      this.floatingWords.push({
        text,
        x: Math.random() * w,
        y: Math.random() * h,
        vx: (Math.random() - 0.5) * 0.02,
        vy: (Math.random() - 0.5) * 0.02,
        alpha: 0.16 + Math.random() * 0.18,
        size: 11 + Math.random() * 10,
      });
    }
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
