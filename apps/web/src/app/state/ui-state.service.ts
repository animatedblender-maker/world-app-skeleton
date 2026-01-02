import { Injectable } from '@angular/core';
import type { CountryModel } from '../data/countries.service';

export type LabelMode = 'all' | 'focus';

@Injectable({ providedIn: 'root' })
export class UiStateService {
  // Search / selection UI state
  labelMode: LabelMode = 'all';
  selectedCountryId: number | null = null;

  // Data shared across features
  countries: CountryModel[] = [];

  setCountries(list: CountryModel[]) {
    this.countries = list || [];
  }

  setSelected(id: number | null) {
    this.selectedCountryId = id;
  }

  setMode(mode: LabelMode) {
    this.labelMode = mode;
  }
}
