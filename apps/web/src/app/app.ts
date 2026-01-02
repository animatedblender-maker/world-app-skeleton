import { AfterViewInit, Component } from '@angular/core';

import { CountriesService, type CountryModel } from './data/countries.service';
import { GlobeService } from './globe/globe.service';
import { UiStateService } from './state/ui-state.service';
import { SearchUiService } from './search/search-ui.service';

import { AuthService, type AuthUser } from './core/services/auth.service';

@Component({
  selector: 'app-root',
  standalone: true,
  templateUrl: './app.html',
})
export class AppComponent implements AfterViewInit {
  private user: AuthUser | null = null;

  constructor(
    private countriesService: CountriesService,
    private globeService: GlobeService,
    private ui: UiStateService,
    private searchUi: SearchUiService,
    private auth: AuthService
  ) {}

  async ngAfterViewInit(): Promise<void> {
    console.log('🚀 App started');

    // 0) Wire Auth UI first (buttons + modals)
    this.wireAuthUi();

    // ✅ Proof + live updates of auth state
    this.auth.currentUser().subscribe((u) => {
      this.user = u;
      this.renderAuthState();

      console.log('🔐 Auth state:', u);
      console.log('🧪 localStorage keys:', Object.keys(localStorage));

      // Supabase usually stores session under keys containing "sb-" and "auth"
      const sbKeys = Object.keys(localStorage).filter(
        (k) => k.includes('sb-') && k.includes('auth')
      );
      console.log('🧪 Supabase auth keys:', sbKeys);
    });

    // 1) Globe
    const globeEl = document.getElementById('globe');
    if (!globeEl) {
      console.error('❌ #globe element not found');
      return;
    }

    console.log('🌍 Initializing globe...');
    this.globeService.init(globeEl);

    // 2) Data (GraphQL-backed in your CountriesService)
    console.log('🗺️ Loading countries (should come from GraphQL)...');
    const t0 = performance.now();
    const data = await this.countriesService.loadCountries();
    const t1 = performance.now();

    this.ui.setCountries(data.countries);
    this.globeService.setData(data);

    console.log(`✅ Countries loaded in ${Math.round(t1 - t0)}ms`);
    console.log('✅ Countries payload keys:', Object.keys(data));
    console.log('✅ First 5 countries:', data.countries.slice(0, 5));

    // Debug proof in window
    (window as any).__countriesFromApi = data.countries;
    console.log('🧪 Debug: window.__countriesFromApi set');

    // 3) Globe click -> sync UI state + search
    this.globeService.onCountryClick((country: CountryModel) => {
      this.ui.setMode('focus');
      this.ui.setSelected(country.id);
      this.searchUi.setInputValue(country.name);
      this.searchUi.setClearButtonVisible(true);
    });

    // 4) Search UI wiring
    this.searchUi.init({
      getCountries: () => this.ui.countries,
      isFocusMode: () => this.ui.labelMode === 'focus',

      onSearch: (country) => {
        this.ui.setMode('focus');
        this.ui.setSelected(country.id);

        this.globeService.selectCountry(country.id);
        this.globeService.showFocusLabel(country.id);
        this.globeService.flyTo(
          country.center.lat,
          country.center.lng,
          country.flyAltitude,
          900
        );
      },

      onClear: () => {
        this.ui.setMode('all');
        this.ui.setSelected(null);
        this.globeService.resetView();
      },
    });

    console.log('✅ Block 2 (Search services) running');
    (window as any).__appReady = true;
  }

  // ---------------------------
  // Auth UI (buttons + modals)
  // ---------------------------

  private wireAuthUi(): void {
    const loginBtn = document.getElementById('loginBtn') as HTMLButtonElement | null;
    const registerBtn = document.getElementById('registerBtn') as HTMLButtonElement | null;
    const logoutBtn = document.getElementById('logoutTopBtn') as HTMLButtonElement | null;

    const loginBackdrop = document.getElementById('loginBackdrop') as HTMLDivElement | null;
    const registerBackdrop = document.getElementById('registerBackdrop') as HTMLDivElement | null;

    const loginClose = document.getElementById('loginCloseBtn') as HTMLButtonElement | null;
    const loginCancel = document.getElementById('loginCancelBtn') as HTMLButtonElement | null;
    const loginSubmit = document.getElementById('loginSubmitBtn') as HTMLButtonElement | null;

    const registerClose = document.getElementById('registerCloseBtn') as HTMLButtonElement | null;
    const registerCancel = document.getElementById('registerCancelBtn') as HTMLButtonElement | null;
    const registerSubmit = document.getElementById('registerSubmitBtn') as HTMLButtonElement | null;

    const loginEmail = document.getElementById('loginEmail') as HTMLInputElement | null;
    const loginPassword = document.getElementById('loginPassword') as HTMLInputElement | null;
    const loginMsg = document.getElementById('loginMsg') as HTMLElement | null;

    const registerEmail = document.getElementById('registerEmail') as HTMLInputElement | null;
    const registerPassword = document.getElementById('registerPassword') as HTMLInputElement | null;
    const registerMsg = document.getElementById('registerMsg') as HTMLElement | null;

    if (!loginBtn || !registerBtn || !logoutBtn) {
      console.warn('⚠️ Auth buttons not found in DOM');
      return;
    }

    const show = (el: HTMLElement | null) => {
      if (!el) return;
      el.style.display = 'flex';
    };
    const hide = (el: HTMLElement | null) => {
      if (!el) return;
      el.style.display = 'none';
    };

    const setMsg = (el: HTMLElement | null, text: string) => {
      if (!el) return;
      el.textContent = text;
    };

    // Open modals
    loginBtn.addEventListener('click', () => {
      setMsg(loginMsg, '');
      show(loginBackdrop);
      loginEmail?.focus();
    });

    registerBtn.addEventListener('click', () => {
      setMsg(registerMsg, '');
      show(registerBackdrop);
      registerEmail?.focus();
    });

    // Close modals
    loginClose?.addEventListener('click', () => hide(loginBackdrop));
    loginCancel?.addEventListener('click', () => hide(loginBackdrop));
    loginBackdrop?.addEventListener('click', (e) => {
      if (e.target === loginBackdrop) hide(loginBackdrop);
    });

    registerClose?.addEventListener('click', () => hide(registerBackdrop));
    registerCancel?.addEventListener('click', () => hide(registerBackdrop));
    registerBackdrop?.addEventListener('click', (e) => {
      if (e.target === registerBackdrop) hide(registerBackdrop);
    });

    // Submit login
    loginSubmit?.addEventListener('click', async () => {
      const email = (loginEmail?.value || '').trim();
      const pass = loginPassword?.value || '';
      if (!email || !pass) {
        setMsg(loginMsg, 'Please enter email + password.');
        return;
      }

      try {
        setMsg(loginMsg, 'Logging in...');
        await this.auth.login(email, pass);
        setMsg(loginMsg, 'Logged in ✅');
        hide(loginBackdrop);
      } catch (e: any) {
        console.error('❌ Login error:', e);
        setMsg(loginMsg, e?.message ?? String(e));
      }
    });

    // Submit register
    registerSubmit?.addEventListener('click', async () => {
      const email = (registerEmail?.value || '').trim();
      const pass = registerPassword?.value || '';
      if (!email || !pass) {
        setMsg(registerMsg, 'Please enter email + password.');
        return;
      }

      try {
        setMsg(registerMsg, 'Registering...');
        await this.auth.register(email, pass);
        setMsg(
          registerMsg,
          'Registered ✅ (If email confirmation is ON, check your email.)'
        );
        hide(registerBackdrop);
      } catch (e: any) {
        console.error('❌ Register error:', e);
        setMsg(registerMsg, e?.message ?? String(e));
      }
    });

    // Logout
    logoutBtn.addEventListener('click', async () => {
      try {
        await this.auth.logout();
      } catch (e) {
        console.error('❌ Logout error:', e);
      }
    });

    // Initial paint
    this.renderAuthState();
  }

  private renderAuthState(): void {
    const authState = document.getElementById('authState');
    const loginBtn = document.getElementById('loginBtn') as HTMLButtonElement | null;
    const registerBtn = document.getElementById('registerBtn') as HTMLButtonElement | null;
    const logoutBtn = document.getElementById('logoutTopBtn') as HTMLButtonElement | null;

    if (authState) {
      authState.textContent = this.user
        ? `Logged in: ${this.user.email ?? 'user'}`
        : 'Not logged in';
    }

    // Toggle buttons
    const loggedIn = !!this.user;
    if (loginBtn) loginBtn.style.display = loggedIn ? 'none' : 'inline-flex';
    if (registerBtn) registerBtn.style.display = loggedIn ? 'none' : 'inline-flex';
    if (logoutBtn) logoutBtn.style.display = loggedIn ? 'inline-flex' : 'none';
  }
}
