/* Castle DOOM's service worker: the site keeps working offline after one
   visit. Network first, so a new deployment arrives as before (the
   browser's HTTP cache still avoids downloading unchanged files); every
   successful GET of the site (the pages, the game's JS, wasm and data zip,
   Freedoom Phase 2 once chosen, the screenshots) and of the Bootstrap CDN
   is copied into the cache, which answers when the network fails.
   Query strings are ignored when matching (castle-doom.js?random_suffix).
   Registered by pages/index.html and the play page (tools/patch_web_page.py). */

const CACHE = 'castle-doom-offline-v2';

/* The game's own files, fetched when the worker installs: the first
   visit's page loaded them before the worker could see the requests.
   (Bootstrap from the CDN and Phase 2 are kept when they are next loaded.) */
const PRECACHE = ['index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png',
  'play/index.html', 'play/castle-doom.js', 'play/castle-doom.wasm', 'play/castle-doom_data.zip'];

self.addEventListener('install', event => {
  self.skipWaiting();
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const path of PRECACHE) {
      try {
        const response = await fetch(path);
        if (response.ok) await cache.put(path, response);
      } catch (error) {
        console.log('Service worker: could not keep ' + path, error);
      }
    }
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys())
      if (key.startsWith('castle-doom-') && key !== CACHE)
        await caches.delete(key);
    await self.clients.claim();
  })());
});

function cacheable(request) {
  if (request.method !== 'GET') return false;
  const url = new URL(request.url);
  return url.origin === self.location.origin || url.hostname === 'cdn.jsdelivr.net';
}

self.addEventListener('fetch', event => {
  const request = event.request;
  if (!cacheable(request)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const response = await fetch(request);
      /* Stored in the background: the page gets the response at once. */
      if (response.ok)
        event.waitUntil(cache.put(request, response.clone()));
      return response;
    } catch (error) {
      let cached = await cache.match(request, { ignoreSearch: true });
      /* A directory URL (play/, the site root) is its index.html. */
      if (!cached && new URL(request.url).pathname.endsWith('/'))
        cached = await cache.match(new URL('index.html', request.url).href, { ignoreSearch: true });
      if (cached) return cached;
      throw error;
    }
  })());
});
