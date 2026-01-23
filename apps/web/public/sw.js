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

  event.waitUntil(self.registration.showNotification(title, options));
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
