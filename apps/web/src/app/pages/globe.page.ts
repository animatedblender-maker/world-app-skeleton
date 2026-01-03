import { AfterViewInit, Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';

import { CountriesService, type CountryModel } from '../data/countries.service';
import { GlobeService } from '../globe/globe.service';
import { UiStateService } from '../state/ui-state.service';
import { SearchUiService } from '../search/search-ui.service';
import { AuthService } from '../core/services/auth.service';
import { GraphqlService } from '../core/services/graphql.service';
import { MediaService } from '../core/services/media.service';


@Component({
  selector: 'app-globe-page',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="topbar">
      <div class="searchwrap">
        <input id="search" placeholder="Search a country on the globe…" />
        <div id="clearBtn" class="clear-btn">×</div>
        <div id="suggestions" class="suggestions"></div>
      </div>
      <button id="go" class="go-btn">GO</button>
    </div>

    <div class="authbar">
  <button class="btn" (click)="logout()">Logout</button>

  <label class="btn" style="cursor:pointer;">
    Upload
    <input type="file" (change)="onFile($event)" style="display:none;" />
  </label>
</div>


    <div class="stats">
      <div><b>Country:</b> <span id="countryPill">Hover / click a country</span></div>
      <div class="row">
        <small id="totalUsers">Total users: —</small>
        <small id="onlineUsers">Online now: —</small>
      </div>
      <div class="row">
        <small id="authState">Logged in</small>
        <small id="heartbeatState">—</small>
      </div>
    </div>

    <div id="globe"></div>
  `,
})
export class GlobePageComponent implements AfterViewInit {
  constructor(
    private countriesService: CountriesService,
    private globeService: GlobeService,
    private ui: UiStateService,
    private searchUi: SearchUiService,
    private auth: AuthService,
    private gql: GraphqlService,
    private router: Router,
    private media: MediaService,

  ) {}
   
  async ngAfterViewInit(): Promise<void> {
    const globeEl = document.getElementById('globe');
    if (!globeEl) {
      console.error('❌ #globe element not found');
      return;
    }

    // 1) Globe
    this.globeService.init(globeEl);

    // 2) Data
    const data = await this.countriesService.loadCountries();
    this.ui.setCountries(data.countries);
    this.globeService.setData(data);

    // 3) Polygon click → UI sync
    this.globeService.onCountryClick((country: CountryModel) => {
      this.ui.setMode('focus');
      this.ui.setSelected(country.id);
      this.searchUi.setInputValue(country.name);
      this.searchUi.setClearButtonVisible(true);
    });

    // 4) Search wiring
    this.searchUi.init({
      getCountries: () => this.ui.countries,
      isFocusMode: () => this.ui.labelMode === 'focus',
      onSearch: (country) => {
        this.ui.setMode('focus');
        this.ui.setSelected(country.id);

        this.globeService.selectCountry(country.id);
        this.globeService.showFocusLabel(country.id);
        this.globeService.flyTo(country.center.lat, country.center.lng, country.flyAltitude, 900);
      },
      onClear: () => {
        this.ui.setMode('all');
        this.ui.setSelected(null);
        this.globeService.resetView();
      },
    });

    // ✅ 5) REAL AUTH TEST (from the app, not playground)
    try {
      const token = await this.auth.getAccessToken();
      console.log('🔑 Supabase access token present?', !!token);

      const result = await this.gql.query<{
        me: { id: string; email?: string | null; role?: string | null } | null;
        privatePing: string;
      }>(`
        query {
          me { id email role }
          privatePing
        }
      `);

      console.log('✅ GraphQL me():', result.me);
      console.log('✅ GraphQL privatePing():', result.privatePing);
    } catch (e: any) {
      console.error('❌ GraphQL test failed:', e?.message ?? e);
    }

    console.log('✅ Globe page ready');
  }

  async logout(): Promise<void> {
    await this.auth.logout();
    await this.router.navigateByUrl('/auth');
  }
 async onFile(e: Event): Promise<void> {
  const input = e.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;

  try {
    const res = await this.media.uploadPostMedia(file);
    console.log('✅ Uploaded path:', res.path);
  } catch (err) {
    console.error('❌ Upload failed:', err);
  } finally {
    input.value = ''; // allow selecting same file again
  }
}


}
