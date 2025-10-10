/* /TripDetails/sw.js */
const VERSION = 'td-v7';                 // bump version
const STATIC_CACHE = `static-${VERSION}`;
const API_PREFIX = '/TripDetails/api/';

// Only auth-agnostic static files here (manifest, icons, pure assets)
const APP_SHELL = [
  '/TripDetails/manifest.webmanifest',
  // e.g., '/TripDetails/icons/icon-192.png',
];

// Helpers unchanged...

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(STATIC_CACHE);
    await Promise.all(APP_SHELL.map(async (url) => {
      try {
        const res = await fetch(url, { cache: 'no-cache' });
        if (res.ok) await cache.put(url, res.clone());
      } catch {}
    }));
    self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(k => k.startsWith('static-') && k !== STATIC_CACHE)
      .map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;

  // 1) API: network only, include cookies
  if (sameOrigin && url.pathname.startsWith(API_PREFIX)) {
    event.respondWith(fetch(req, { cache: 'no-store', credentials: 'include' }));
    return;
  }

  // 2) Navigations: network **always**, no-store
  if (req.mode === 'navigate') {
    event.respondWith(fetch(req, { cache: 'no-store', credentials: 'include' })
      .catch(() => new Response('Offline', { status: 503 })));
    return;
  }

  // 3) Same-origin static: cache-first (unchanged)
  if (sameOrigin && req.method === 'GET') {
    event.respondWith((async () => {
      const cache = await caches.open(STATIC_CACHE);
      const hit = await cache.match(req);
      if (hit) return hit;
      const res = await fetch(req);
      if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
      return res;
    })());
    return;
  }

  // 4) Cross-origin: pass-through with light SWR
  event.respondWith((async () => {
    const cache = await caches.open(STATIC_CACHE);
    const hit = await cache.match(req);
    const p = fetch(req).then(res => {
      if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
      return res;
    }).catch(() => hit || new Response('Offline', { status: 503 }));
    return hit || p;
  })());
});

self.addEventListener('message', (event) => {
  if (event.data === 'SW_SKIP_WAITING') self.skipWaiting();
});