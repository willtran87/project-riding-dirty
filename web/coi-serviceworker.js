const ISOLATION_HEADERS = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Cross-Origin-Resource-Policy': 'same-origin',
};

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (
    new URL(request.url).origin !== self.location.origin
    || (request.cache === 'only-if-cached' && request.mode !== 'same-origin')
  ) {
    return;
  }

  event.respondWith(
    fetch(request).then((response) => {
      if (response.type === 'opaque' || response.type === 'opaqueredirect') {
        return response;
      }
      const headers = new Headers(response.headers);
      for (const [name, value] of Object.entries(ISOLATION_HEADERS)) {
        headers.set(name, value);
      }
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    }),
  );
});
