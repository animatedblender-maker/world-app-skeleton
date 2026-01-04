import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';

@Injectable({ providedIn: 'root' })
export class MediaService {
  // Keep your existing post media upload (bucket: media)
  async uploadPostMedia(file: File): Promise<{ path: string; publicUrl: string }> {
    const ext = (file.name.split('.').pop() || 'bin').toLowerCase();
    const path = `posts/${crypto.randomUUID()}.${ext}`;

    const { error } = await supabase.storage.from('media').upload(path, file, {
      upsert: false,
      cacheControl: '3600',
      contentType: file.type || 'application/octet-stream',
    });
    if (error) throw error;

    const { data } = supabase.storage.from('media').getPublicUrl(path);
    return { path, publicUrl: data.publicUrl };
  }

  // ✅ Full MVP: avatar upload (bucket: avatars)
  // - path is clean: "<userId>/<uuid>.<ext>"
  // - returns a signed URL (works even if bucket is private)
  async uploadAvatar(file: File): Promise<{ path: string; url: string }> {
    const { data: sessionData, error: sessionErr } = await supabase.auth.getSession();
    if (sessionErr) throw sessionErr;
    const userId = sessionData.session?.user?.id;
    if (!userId) throw new Error('Not authenticated');

    const ext = (file.name.split('.').pop() || 'png').toLowerCase();
    const key = `${userId}/${crypto.randomUUID()}.${ext}`;

    const { error: uploadErr } = await supabase.storage.from('avatars').upload(key, file, {
      upsert: true,
      cacheControl: '3600',
      contentType: file.type || 'image/*',
    });
    if (uploadErr) throw uploadErr;

    // Signed URL works regardless of bucket public/private
    const { data: signed, error: signedErr } = await supabase.storage
      .from('avatars')
      .createSignedUrl(key, 60 * 60 * 24 * 30); // 30 days

    if (signedErr || !signed?.signedUrl) {
      // fallback to public url if signed fails
      const { data } = supabase.storage.from('avatars').getPublicUrl(key);
      return { path: key, url: data.publicUrl };
    }

    return { path: key, url: signed.signedUrl };
  }
}
