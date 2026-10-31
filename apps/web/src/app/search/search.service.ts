import { Injectable } from '@angular/core';
import type { CountryModel } from '../data/countries.service';

@Injectable({ providedIn: 'root' })
export class SearchService {
  normalizeName(s: string): string {
    return (s || '')
      .trim()
      .toLowerCase()
      .replace(/\s+/g, ' ')
      .replace(/[’']/g, '')
      .replace(/[^a-z0-9 ]/g, '');
  }

  prefixSuggest(countries: CountryModel[], query: string, limit = 8): CountryModel[] {
    const q = this.normalizeName(query);
    if (!q) return [];
    const out: CountryModel[] = [];
    for (const c of countries) {
      if (c.norm.startsWith(q)) out.push(c);
      if (out.length >= limit) break;
    }
    return out;
  }

  bestCandidateForSearch(
    countries: CountryModel[],
    input: string,
    visibleSuggestions: CountryModel[],
    activeSuggestionIndex: number
  ): CountryModel | null {
    const raw = (input || '').trim();
    if (!raw) return null;

    if (visibleSuggestions.length) {
      const idx = activeSuggestionIndex >= 0 ? activeSuggestionIndex : 0;
      return visibleSuggestions[idx] || null;
    }

    const nq = this.normalizeName(raw);
    return countries.find((c) => c.norm === nq) || null;
  }
}
