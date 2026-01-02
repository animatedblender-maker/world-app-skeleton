import { Component, AfterViewInit } from '@angular/core';
import { CountriesService, type CountryModel } from './data/countries.service';
import { GlobeService } from './globe/globe.service';
import { UiStateService } from './state/ui-state.service';
import { SearchUiService } from './search/search-ui.service';
import { AuthService } from './core/services/auth.service';

@Component({
  selector: 'app-root',
  standalone: true,
  templateUrl: './app.html',
})
export class AppComponent implements AfterViewInit {
  constructor(
    private countriesService: CountriesService,
    private globeService: GlobeService,
    private ui: UiStateService,
    private searchUi: SearchUiService,
    private auth: AuthService
  ) {}

  async ngAfterViewInit(): Promise<void> {
    console.log('🚀 App started');

    this.initAuthButtons();

    const globeEl = document.getElementById('globe');
    if (!globeEl) {
      console.error('❌ #globe element not found');
      return;
    }

    // 1) Globe
    this.globeService.init(globeEl);

    // 2) Data (still from GraphQL)
    const data = await this.countriesService.loadCountries();
    this.ui.setCountries(data.countries);
    this.globeService.setData(data);

    // 3) Globe click sync
    this.globeService.onCountryClick((country: CountryModel) => {
      this.ui.setMode('focus');
      this.ui.setSelected(country.id);
      this.searchUi.setInputValue(country.name);
      this.searchUi.setClearButtonVisible(true);
    });

    // 4) Search UI
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

    console.log('✅ Globe + Search running');
  }

  private initAuthButtons() {
    const loginBtn = document.getElementById('btnLogin');
    const registerBtn = document.getElementById('btnRegister');
    const userLabel = document.getElementById('authUserLabel');

    const setLabel = (text: string) => {
      if (userLabel) userLabel.textContent = text;
    };

    this.auth.currentUser().subscribe((u) => {
      setLabel(u ? `Logged in: ${u.email}` : 'Not logged in');
      console.log('🔐 Auth state:', u);
    });

    loginBtn?.addEventListener('click', async () => {
      try {
        const email = prompt('Login email:') || '';
        const password = prompt('Password:') || '';
        const u = await this.auth.login(email, password);
        console.log('✅ Logged in:', u);
      } catch (e: any) {
        alert(`Login failed: ${e?.message || e}`);
      }
    });

    registerBtn?.addEventListener('click', async () => {
      try {
        const email = prompt('Register email:') || '';
        const password = prompt('Password (min 6 chars):') || '';
        const u = await this.auth.register(email, password);
        console.log('✅ Registered:', u);
        alert(
          'Registered! If email confirmation is ON in Supabase, check your email before login works.'
        );
      } catch (e: any) {
        alert(`Register failed: ${e?.message || e}`);
      }
    });

    // Dev shortcut: right-click Login -> logout
    loginBtn?.addEventListener('contextmenu', async (e) => {
      e.preventDefault();
      await this.auth.logout();
      console.log('🚪 Logged out');
    });
  }
}
