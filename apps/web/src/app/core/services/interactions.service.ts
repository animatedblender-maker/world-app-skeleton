import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';

export type InteractionType =
  | 'click_country'
  | 'search_country'
  | 'visit_country';

@Injectable({ providedIn: 'root' })
export class InteractionsService {
  async log(input: {
    type: InteractionType;
    country_id?: number | null;
    country_code?: string | null;
    payload?: any;
  }): Promise<void> {
    const { error } = await supabase.from('interactions').insert({
      type: input.type,
      country_id: input.country_id ?? null,
      country_code: input.country_code ?? null,
      payload: input.payload ?? null,
    });

    if (error) console.warn('⚠️ interaction log failed:', error.message);
  }
}
