import { Injectable } from '@angular/core';
import type { CountryModel } from '../data/countries.service';
import { SearchService } from './search.service';

type SearchUiHooks = {
  getCountries: () => CountryModel[];
  onSearch: (country: CountryModel) => void;
  onClear: () => void;
  isFocusMode: () => boolean;
};

@Injectable({ providedIn: 'root' })
export class SearchUiService {
  private searchInput: HTMLInputElement | null = null;
  private clearBtn: HTMLElement | null = null;
  private goBtn: HTMLElement | null = null;
  private suggEl: HTMLElement | null = null;

  private visibleSuggestions: CountryModel[] = [];
  private activeSuggestionIndex = -1;

  private hooks: SearchUiHooks | null = null;

  constructor(private search: SearchService) {}

  init(hooks: SearchUiHooks): void {
    this.hooks = hooks;

    this.searchInput = document.getElementById('search') as HTMLInputElement | null;
    this.clearBtn = document.getElementById('clearBtn');
    this.goBtn = document.getElementById('go');
    this.suggEl = document.getElementById('suggestions');

    if (!this.searchInput || !this.clearBtn || !this.goBtn || !this.suggEl) {
      console.warn('Search UI elements not found. Check app.html ids: search, clearBtn, go, suggestions.');
      return;
    }

    // click outside suggestions closes
    document.addEventListener('mousedown', (e) => {
      const t = e.target as any;
      if (!this.suggEl) return;
      if (!this.suggEl.contains(t) && t !== this.searchInput) this.clearSuggestions();
    });

    // clear button
    this.clearBtn.addEventListener('click', () => {
      hooks.onClear();
      this.setInputValue('');
      this.setClearButtonVisible(false);
      this.clearSuggestions();
    });

    // input => suggestions
    this.searchInput.addEventListener('input', () => {
      const raw = (this.searchInput?.value || '').trim();
      this.setClearButtonVisible(hooks.isFocusMode() || raw.length > 0);
      this.updateSuggestions();
    });

    // GO
    this.goBtn.addEventListener('click', () => this.runSearch());

    // keyboard
    this.searchInput.addEventListener('keydown', (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        hooks.onClear();
        this.setInputValue('');
        this.setClearButtonVisible(false);
        this.clearSuggestions();
        return;
      }

      const suggOpen = this.suggEl?.style.display === 'block';
      if (suggOpen && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
        e.preventDefault();
        const max = this.visibleSuggestions.length - 1;
        if (max < 0) return;

        if (e.key === 'ArrowDown') {
          this.setActiveSuggestion(this.activeSuggestionIndex < max ? this.activeSuggestionIndex + 1 : 0);
        } else {
          this.setActiveSuggestion(this.activeSuggestionIndex > 0 ? this.activeSuggestionIndex - 1 : max);
        }
        return;
      }

      if (e.key === 'Enter') this.runSearch();
    });

    // initial
    this.setClearButtonVisible(false);
    this.clearSuggestions();
  }

  setInputValue(name: string) {
    if (this.searchInput) this.searchInput.value = name || '';
  }

  setClearButtonVisible(show: boolean) {
    if (!this.clearBtn) return;
    this.clearBtn.style.display = show ? 'flex' : 'none';
  }

  /** ---------- suggestions ---------- */

  private updateSuggestions(): void {
    if (!this.hooks) return;
    const countries = this.hooks.getCountries();
    const raw = (this.searchInput?.value || '').trim();

    if (!raw || !countries.length) {
      this.clearSuggestions();
      return;
    }

    const list = this.search.prefixSuggest(countries, raw, 8);
    this.renderSuggestions(list);
  }

  private renderSuggestions(list: CountryModel[]): void {
    this.visibleSuggestions = list;
    this.activeSuggestionIndex = -1;

    if (!this.suggEl) return;

    if (!list.length) {
      this.clearSuggestions();
      return;
    }

    this.suggEl.innerHTML = list
      .map((c, idx) => `<div class="suggestion-item" data-idx="${idx}">${c.name}</div>`)
      .join('');
    this.suggEl.style.display = 'block';

    const items = [...this.suggEl.querySelectorAll('.suggestion-item')];
    items.forEach((item) => {
      item.addEventListener('mousedown', (e) => {
        e.preventDefault();
        const idx = Number((item as HTMLElement).getAttribute('data-idx'));
        const c = this.visibleSuggestions[idx];
        if (!c || !this.hooks) return;

        this.setInputValue(c.name);
        this.clearSuggestions();
        this.hooks.onSearch(c);
        this.setClearButtonVisible(true);
      });
    });
  }

  private setActiveSuggestion(idx: number): void {
    this.activeSuggestionIndex = idx;
    const el = this.suggEl;
    if (!el) return;
    const items = [...el.querySelectorAll('.suggestion-item')];
    items.forEach((node, i) => (node as HTMLElement).classList.toggle('active', i === idx));
  }

  private clearSuggestions(): void {
    this.visibleSuggestions = [];
    this.activeSuggestionIndex = -1;

    if (this.suggEl) {
      this.suggEl.style.display = 'none';
      this.suggEl.innerHTML = '';
    }
  }

  /** ---------- run search ---------- */

  private runSearch(): void {
    if (!this.hooks) return;
    const countries = this.hooks.getCountries();

    const found = this.search.bestCandidateForSearch(
      countries,
      this.searchInput?.value || '',
      this.visibleSuggestions,
      this.activeSuggestionIndex
    );

    if (!found) {
      alert('No match. Type the first letters to see suggestions.');
      return;
    }

    this.clearSuggestions();
    this.hooks.onSearch(found);
    this.setClearButtonVisible(true);
  }
}
