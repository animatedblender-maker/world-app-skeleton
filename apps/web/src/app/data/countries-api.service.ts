import { Injectable } from '@angular/core';
import { BehaviorSubject, map, Observable, of, tap } from 'rxjs';
import { GraphqlService } from '../core/services/graphql.service';

export type CountryModel = {
  id: number;
  name: string;
  iso: string;
  continent: string;
  lat: number;
  lng: number;
};

type CountriesQueryData = {
  countries: CountryModel[];
};

type CountryByIsoQueryData = {
  countryByIso: CountryModel | null;
};

@Injectable({ providedIn: 'root' })
export class CountriesApiService {
  private readonly countries$ = new BehaviorSubject<CountryModel[] | null>(null);

  constructor(private gql: GraphqlService) {}

  loadCountries(): Observable<CountryModel[]> {
    const cached = this.countries$.value;
    if (cached) return of(cached);

    const query = /* GraphQL */ `
      query Countries {
        countries {
          id
          name
          iso
          continent
          lat
          lng
        }
      }
    `;

    return this.gql.query<CountriesQueryData>(query).pipe(
      map((d) => d.countries),
      tap((list) => this.countries$.next(list))
    );
  }

  getCountries(): Observable<CountryModel[]> {
    const cached = this.countries$.value;
    return cached ? of(cached) : this.loadCountries();
  }

  searchByName(term: string): Observable<CountryModel[]> {
    const q = (term ?? '').trim().toLowerCase();
    if (!q) return of([]);

    return this.getCountries().pipe(
      map((countries) =>
        countries
          .filter((c) => c.name.toLowerCase().includes(q))
          .slice(0, 12)
      )
    );
  }

  getByIso(iso: string): Observable<CountryModel | null> {
    const query = /* GraphQL */ `
      query CountryByIso($iso: String!) {
        countryByIso(iso: $iso) {
          id
          name
          iso
          continent
          lat
          lng
        }
      }
    `;

    return this.gql
      .query<CountryByIsoQueryData, { iso: string }>(query, {
        iso: String(iso || '').toUpperCase(),
      })
      .pipe(map((d) => d.countryByIso));
  }
}
