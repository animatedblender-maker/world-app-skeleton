import { Injectable } from '@angular/core';
import { continentColors, oceanColor } from './palette';
import type { CountryModel } from '../data/countries.service';

declare const Globe: any;

@Injectable({ providedIn: 'root' })
export class GlobeService {
  private globe: any | null = null;

  private features: any[] = [];
  private countries: CountryModel[] = [];
  private selectedId: number | null = null;

  private countryClickCb: ((country: CountryModel) => void) | null = null;

  init(globeEl: HTMLElement): void {
    const globe = Globe()(globeEl)
      .backgroundColor('#f5f6f8')
      .showAtmosphere(true)
      .atmosphereColor('#b8d7ff')
      .atmosphereAltitude(0.1);

    globe.globeMaterial().color.set(oceanColor);
    globe.globeMaterial().emissive.set(oceanColor);
    globe.globeMaterial().emissiveIntensity = 0.22;
    globe.globeMaterial().shininess = 7;

    globe.pointOfView({ lat: 20, lng: 0, altitude: 2.25 }, 0);
    globe.controls().autoRotate = false;
    globe.controls().enableDamping = true;
    globe.controls().dampingFactor = 0.08;
    globe.controls().rotateSpeed = 0.55;
    globe.controls().zoomSpeed = 0.8;
    globe.controls().minDistance = 120;
    globe.controls().maxDistance = 520;

    globe
      .labelsData([])
      .labelLat((d: any) => d.lat)
      .labelLng((d: any) => d.lng)
      .labelText((d: any) => d.name)
      .labelColor(() => 'rgba(255,255,255,0.90)')
      .labelDotRadius(() => 0)
      .labelAltitude(() => 0.012)
      .labelResolution(3)
      .labelSize((d: any) => d.size);

    window.addEventListener('resize', () => {
      try {
        globe.width(window.innerWidth);
        globe.height(window.innerHeight);
      } catch {}
    });

    this.globe = globe;
  }

  onCountryClick(cb: (country: CountryModel) => void) {
    this.countryClickCb = cb;
  }

  setData(payload: { features: any[]; countries: CountryModel[] }): void {
    if (!this.globe) throw new Error('Globe not initialized');
    this.features = payload.features;
    this.countries = payload.countries;

    const globe = this.globe;

    globe
      .polygonsData(this.features)
      .polygonCapColor((f: any) => this.polygonCapColorFn(f))
      .polygonSideColor(() => 'rgba(0,0,0,0)')
      .polygonStrokeColor(() => 'rgba(255,255,255,0.20)')
      .polygonAltitude((f: any) => this.polygonAltitudeFn(f));

    this.showAllLabels();

    globe.onPolygonClick((f: any) => {
      const found = this.countries.find((c) => c.id === f?.__id);
      if (!found) return;

      this.selectCountry(found.id);
      this.flyTo(found.center.lat, found.center.lng, found.flyAltitude, 900);
      this.showFocusLabel(found.id);

      this.countryClickCb?.(found);
    });
  }

  showAllLabels(): void {
    if (!this.globe) return;
    this.globe.labelsData(
      this.countries.map((c) => ({ name: c.name, lat: c.center.lat, lng: c.center.lng, size: c.labelSize }))
    );
  }

  showFocusLabel(countryId: number): void {
    if (!this.globe) return;
    const c = this.countries.find((x) => x.id === countryId);
    this.globe.labelsData(
      c ? [{ name: c.name, lat: c.center.lat, lng: c.center.lng, size: Math.min(1.35, c.labelSize + 0.25) }] : []
    );
  }

  selectCountry(countryId: number | null): void {
    this.selectedId = countryId;
    this.refreshPolygons();
  }

  flyTo(lat: number, lng: number, altitude: number, ms = 900): void {
    if (!this.globe) return;
    this.globe.pointOfView({ lat, lng, altitude }, ms);
  }

  resetView(): void {
    this.selectCountry(null);
    this.showAllLabels();
    this.flyTo(20, 0, 2.25, 800);
  }

  private refreshPolygons(): void {
    if (!this.globe) return;
    this.globe.polygonCapColor((f: any) => this.polygonCapColorFn(f));
    this.globe.polygonAltitude((f: any) => this.polygonAltitudeFn(f));
  }

  private polygonCapColorFn(f: any): string {
    if (this.selectedId && f?.__id === this.selectedId) return 'rgba(255,255,255,0.35)';
    const cont = this.getContinent(f);
    return continentColors[cont] || continentColors['Unknown'];
  }

  private polygonAltitudeFn(f: any): number {
    if (this.selectedId && f?.__id === this.selectedId) return 0.01;
    return 0.006;
  }

  private getContinent(f: any): string {
    const p = f?.properties || {};
    const c = p.CONTINENT || p.continent || p.REGION_UN || p.REGION_WB || p.SUBREGION || p.region || null;

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
}
