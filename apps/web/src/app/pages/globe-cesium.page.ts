import { AfterViewInit, Component, ElementRef, NgZone, OnDestroy, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { BottomTabsComponent } from '../components/bottom-tabs.component';

import { CountriesService } from '../data/countries.service';
import { PresenceService } from '../core/services/presence.service';
import type { ConnectionPoint } from '../globe/globe.service';

@Component({
  selector: 'app-globe-cesium-page',
  standalone: true,
  imports: [CommonModule, BottomTabsComponent],
  template: `
    <div class="cesium-shell">
      <div class="cesium-top">
        <button class="cesium-back" type="button" (click)="goBack()">Back</button>
        <div class="cesium-title">Cesium Prototype</div>
        <div class="cesium-sub">3D globe + boundaries + live dots</div>
      </div>
      <div #cesiumContainer class="cesium-container"></div>
    </div>
    <app-bottom-tabs></app-bottom-tabs>
  `,
  styles: [
    `
    :host{
      display:block;
      height:100%;
    }
    .cesium-shell{
      position:relative;
      min-height:100vh;
      background:radial-gradient(circle at 30% 15%, rgba(18,74,98,0.75), #0b2a3b 55%, #071924 100%);
      overflow:hidden;
      padding-bottom: var(--tabs-safe, 64px);
      box-sizing: border-box;
    }
    .cesium-top{
      position:absolute;
      top:16px;
      left:16px;
      z-index:5;
      display:flex;
      align-items:center;
      gap:12px;
      color:#eaf3ff;
      background:rgba(6,14,24,0.6);
      border:1px solid rgba(92,160,210,0.2);
      padding:10px 14px;
      border-radius:16px;
      backdrop-filter:blur(10px);
      flex-wrap:wrap;
    }
    .cesium-back{
      border:0;
      background:#1c6aa2;
      color:#fff;
      padding:6px 12px;
      border-radius:12px;
      cursor:pointer;
      font-weight:600;
    }
    .cesium-title{
      font-weight:700;
      letter-spacing:0.02em;
    }
    .cesium-sub{
      font-size:12px;
      opacity:0.8;
    }
    .cesium-container{
      position:absolute;
      inset:0;
    }
    .cesium-shell .cesium-credit-compact{
      right:12px !important;
      top:12px !important;
      bottom:auto !important;
      background:rgba(4,12,20,0.55);
      border-radius:10px;
      padding:4px 8px;
      font-size:10px !important;
      opacity:0.8;
    }
    .cesium-shell .cesium-credit-compact img{
      height:12px !important;
    }
    .cesium-shell .cesium-credit-compact a{
      color:#cfe6ff !important;
      text-decoration:none !important;
    }
    `
  ],
})
export class GlobeCesiumPageComponent implements AfterViewInit, OnDestroy {
  @ViewChild('cesiumContainer', { static: true }) containerRef!: ElementRef<HTMLDivElement>;

  private viewer: any = null;
  private pointsSource: any = null;
  private lastPointsTs = 0;

  constructor(
    private zone: NgZone,
    private router: Router,
    private countriesService: CountriesService,
    private presence: PresenceService
  ) {}

  async ngAfterViewInit(): Promise<void> {
    this.zone.runOutsideAngular(async () => {
      const Cesium = await this.ensureCesium();
      if (!Cesium) return;

      const container = this.containerRef?.nativeElement;
      if (!container) return;

      const viewer = new Cesium.Viewer(container, {
        animation: false,
        timeline: false,
        geocoder: false,
        homeButton: false,
        baseLayerPicker: false,
        sceneModePicker: false,
        navigationHelpButton: false,
        infoBox: false,
        selectionIndicator: false,
        fullscreenButton: false,
        shouldAnimate: true,
      });

      const assetBase = new URL('./', document.baseURI).toString();
      const dayProvider = new Cesium.SingleTileImageryProvider({
        url: new URL('earth-day-8k.jpg?v=4', assetBase).toString(),
        rectangle: Cesium.Rectangle.fromDegrees(-180, -90, 180, 90),
        credit: 'Solar System Scope',
      });
      const cloudsProvider = new Cesium.SingleTileImageryProvider({
        url: new URL('earth-clouds-8k.jpg?v=3', assetBase).toString(),
        rectangle: Cesium.Rectangle.fromDegrees(-180, -90, 180, 90),
        credit: 'Solar System Scope',
      });
      const osmProvider = new Cesium.UrlTemplateImageryProvider({
        url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        credit: '© OpenStreetMap contributors',
      });
      viewer.imageryLayers.removeAll();
      const dayLayer = viewer.imageryLayers.addImageryProvider(dayProvider);
      const cloudsLayer = viewer.imageryLayers.addImageryProvider(cloudsProvider);
      const osmLayer = viewer.imageryLayers.addImageryProvider(osmProvider);
      osmLayer.alpha = 0;
      cloudsLayer.alpha = 0.45;

      viewer.scene.globe.enableLighting = false;
      viewer.scene.globe.maximumScreenSpaceError = 1.25;
      viewer.scene.globe.baseColor = Cesium.Color.fromCssColorString('#0b2a3b');
      viewer.scene.backgroundColor = Cesium.Color.fromCssColorString('#0b2a3b');
      viewer.scene.skyAtmosphere.show = false;
      viewer.scene.globe.showGroundAtmosphere = false;
      viewer.scene.postProcessStages.fxaa.enabled = true;
      viewer.resolutionScale = Math.min(2, window.devicePixelRatio || 1);
      viewer.cesiumWidget.creditContainer?.classList.add('cesium-credit-compact');
      viewer.scene.skyBox = undefined;

      try {
        const brightness = Cesium.PostProcessStageLibrary.createBrightnessStage();
        brightness.uniforms.brightness = 1.06;
        const contrast = Cesium.PostProcessStageLibrary.createContrastStage();
        contrast.uniforms.contrast = 1.12;
        const saturation = Cesium.PostProcessStageLibrary.createSaturationStage();
        saturation.uniforms.saturation = 0.92;
        viewer.scene.postProcessStages.add(brightness);
        viewer.scene.postProcessStages.add(contrast);
        viewer.scene.postProcessStages.add(saturation);
      } catch {}

      dayLayer.alpha = 1;

      const updateLayerBlend = () => {
        const height = viewer.camera.positionCartographic.height;
        const t = Cesium.Math.clamp((height - 300_000) / 2_500_000, 0, 1);
        const osmAlpha = 0.1 + 0.9 * (1 - t);
        const dayAlpha = 0.35 + 0.65 * t;
        const cloudsAlpha = 0.2 + 0.35 * t;
        osmLayer.alpha = osmAlpha;
        dayLayer.alpha = dayAlpha;
        cloudsLayer.alpha = cloudsAlpha;
      };
      updateLayerBlend();
      viewer.camera.changed.addEventListener(updateLayerBlend);
      viewer.scene.screenSpaceCameraController.maximumZoomDistance = 60_000_000;
      viewer.scene.screenSpaceCameraController.minimumZoomDistance = 600_000;

      this.viewer = viewer;
      this.pointsSource = new Cesium.CustomDataSource('presence');
      viewer.dataSources.add(this.pointsSource);

      try {
        const ds = await Cesium.GeoJsonDataSource.load('assets/countries50m.geojson', {
          stroke: Cesium.Color.fromCssColorString('#2a4c66'),
          fill: Cesium.Color.fromCssColorString('#0b273d').withAlpha(0.25),
          strokeWidth: 1.0,
        });
        viewer.dataSources.add(ds);
        ds.entities.values.forEach((entity: any) => {
          if (entity.polygon) {
            entity.polygon.outline = true;
            entity.polygon.outlineColor = Cesium.Color.fromCssColorString('#2a4c66');
          }
        });
      } catch {}

      const countriesPayload = await this.countriesService.loadCountries();

      try {
        await this.presence.start({
          countries: countriesPayload.countries,
          onUpdate: (snap) => {
            this.updatePoints(Cesium, snap.points);
          },
        });
      } catch {}
    });
  }

  ngOnDestroy(): void {
    try { this.presence.stop(); } catch {}
    if (this.viewer) {
      try { this.viewer.destroy(); } catch {}
      this.viewer = null;
    }
  }

  goBack(): void {
    void this.router.navigate(['/globe']);
  }

  private updatePoints(Cesium: any, points: ConnectionPoint[]): void {
    if (!this.pointsSource) return;
    const now = Date.now();
    if (now - this.lastPointsTs < 600) return;
    this.lastPointsTs = now;

    this.pointsSource.entities.removeAll();
    for (const point of points) {
      const lat = Number(point.lat);
      const lng = Number(point.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      const size = Math.max(2, Math.round((point.radius ?? 1.2) * 1.8));
      const color = Cesium.Color.fromCssColorString(point.color || 'rgba(0,255,209,0.92)');
      this.pointsSource.entities.add({
        position: Cesium.Cartesian3.fromDegrees(lng, lat),
        point: {
          pixelSize: size,
          color,
          outlineColor: Cesium.Color.fromCssColorString('#04141f'),
          outlineWidth: 1,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
      });
    }
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
