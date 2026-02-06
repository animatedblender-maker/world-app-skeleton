const SW_VERSION = '2026-02-04-1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  const title = data.title || 'Matterya';
  const options = {
    body: data.body || '',
    icon: data.icon || '/logo.png',
    badge: data.badge || '/logo.png',
    data: {
      url: data.url || '/',
    },
    tag: data.tag || undefined,
  };

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientsArr) => {
        let targetPath = '';
        let targetChat = '';
        try {
          const targetUrl = new URL(data.url || '/', self.location.origin);
          targetPath = targetUrl.pathname;
          targetChat = targetUrl.searchParams.get('c') || '';
        } catch {}

        if (targetPath.startsWith('/messages')) {
          const inSameChat = clientsArr.some((client) => {
            if (client.visibilityState !== 'visible') return false;
            try {
              const url = new URL(client.url);
              if (!url.pathname.startsWith('/messages')) return false;
              if (!targetChat) return true;
              return url.searchParams.get('c') === targetChat;
            } catch {
              return false;
            }
          });
          if (inSameChat) return;
        }

        return self.registration.showNotification(title, options);
      })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification?.data?.url || '/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientsArr) => {
      const targetUrl = new URL(url, self.location.origin).href;
      for (const client of clientsArr) {
        if (client.url === targetUrl) {
          return client.focus();
        }
      }
      return self.clients.openWindow(targetUrl);
    })
  );
});
