import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';

@Injectable({ providedIn: 'root' })
export class MediaService {
  // Keep your existing post media upload (bucket: posts)
  async uploadPostMedia(file: File): Promise<{ path: string; publicUrl: string }> {
    const { data: sessionData, error: sessionErr } = await supabase.auth.getSession();
    if (sessionErr) throw sessionErr;
    const userId = sessionData.session?.user?.id;
    if (!userId) throw new Error('Not authenticated');

    const ext = (file.name.split('.').pop() || 'bin').toLowerCase();
    const path = `${userId}/${crypto.randomUUID()}.${ext}`;

    const { error } = await supabase.storage.from('posts').upload(path, file, {
      upsert: false,
      cacheControl: '3600',
      contentType: file.type || 'application/octet-stream',
    });
    if (error) throw error;

    const { data } = supabase.storage.from('posts').getPublicUrl(path);
    return { path, publicUrl: data.publicUrl };
  }

  async uploadMessageMedia(
    file: File,
    conversationId: string
  ): Promise<{ path: string; name: string; mime: string; size: number }> {
    const { data: sessionData, error: sessionErr } = await supabase.auth.getSession();
    if (sessionErr) throw sessionErr;
    const userId = sessionData.session?.user?.id;
    if (!userId) throw new Error('Not authenticated');

    const ext = (file.name.split('.').pop() || 'bin').toLowerCase();
    const safeName = file.name || `message.${ext}`;
    const path = `${userId}/${conversationId}/${crypto.randomUUID()}.${ext}`;

    const { error } = await supabase.storage.from('messages').upload(path, file, {
      upsert: false,
      cacheControl: '3600',
      contentType: file.type || 'application/octet-stream',
    });
    if (error) throw error;

    return { path, name: safeName, mime: file.type || 'application/octet-stream', size: file.size };
  }

  // ✅ Avatar upload (bucket: avatars)
  // - blocks GIF
  // - accepts a File (we will pass a cropped File from the cropper)
  async uploadAvatar(file: File): Promise<{ path: string; url: string }> {
    // Block GIF for now
    const ext = (file.name.split('.').pop() || '').toLowerCase();
    if (ext === 'gif' || file.type === 'image/gif') {
      throw new Error('GIF avatars are disabled for now. Please upload PNG/JPG/WebP.');
    }

    const { data: sessionData, error: sessionErr } = await supabase.auth.getSession();
    if (sessionErr) throw sessionErr;
    const userId = sessionData.session?.user?.id;
    if (!userId) throw new Error('Not authenticated');

    const safeExt = (ext || 'png').toLowerCase();
    const key = `${userId}/${crypto.randomUUID()}.${safeExt}`;

    const { error: uploadErr } = await supabase.storage.from('avatars').upload(key, file, {
      upsert: true,
      cacheControl: '3600',
      contentType: file.type || 'image/png',
    });
    if (uploadErr) throw uploadErr;

    const { data: signed, error: signedErr } = await supabase.storage
      .from('avatars')
      .createSignedUrl(key, 60 * 60 * 24 * 30); // 30 days

    if (!signedErr && signed?.signedUrl) {
      return { path: key, url: signed.signedUrl };
    }

    const { data } = supabase.storage.from('avatars').getPublicUrl(key);
    return { path: key, url: data.publicUrl };
  }
}
