import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';

@Injectable({ providedIn: 'root' })
export class MediaService {
  async uploadPostMedia(file: File): Promise<{ path: string }> {
    const { data } = await supabase.auth.getSession();
    const userId = data.session?.user?.id;
    if (!userId) throw new Error('Not logged in');

    if (!file.type.startsWith('image/') && !file.type.startsWith('video/')) {
      throw new Error(`Unsupported media type: ${file.type || 'unknown'}`);
    }

    const safeName = (file.name || 'file')
      .replace(/\s+/g, '_')
      .replace(/[^a-zA-Z0-9._-]/g, '');

    const path = `${userId}/${Date.now()}_${safeName}`;

    const { error } = await supabase.storage.from('posts').upload(path, file, {
      cacheControl: '3600',
      upsert: false,
      contentType: file.type,
    });

    if (error) throw error;
    return { path };
  }

  async getSignedUrl(path: string, seconds = 3600): Promise<string> {
    const { data, error } = await supabase.storage.from('posts').createSignedUrl(path, seconds);
    if (error) throw error;
    return data.signedUrl;
  }
}
