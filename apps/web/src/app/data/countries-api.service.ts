import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { GraphqlService } from '../core/services/graphql.service';

export type CountryModel = {
  id: string;
  name: string;
  iso: string;
  continent?: string | null;
  center?: { lat: number; lng: number } | null;
};

type CountriesQueryData = {
  countries: { countries: CountryModel[] };
};

@Injectable({ providedIn: 'root' })
export class CountriesApiService {
  countries$ = new BehaviorSubject<CountryModel[] | null>(null);

  constructor(private gql: GraphqlService) {}

  async refreshCountries(): Promise<CountryModel[]> {
    const query = `
      query {
        countries {
          countries {
            id
            name
            iso
            continent
            center { lat lng }
          }
        }
      }
    `;

    const d = await this.gql.query<CountriesQueryData>(query);
    const list = d.countries.countries;
    this.countries$.next(list);
    return list;
  }

  async me(): Promise<{ id: string; email?: string | null } | null> {
    const query = `query { me { id email } }`;
    const d = await this.gql.query<{ me: { id: string; email?: string | null } | null }>(query);
    return d.me;
  }
}
