// FleetPay Service Worker — PWA com cache network-first para HTML
// Versão: 2026-05-01-v1
//
// Estratégia:
//   - HTML, JSON, JS de origem própria → network-first (apanha sempre versão nova quando online)
//   - Assets externos (CDN, Supabase) → passa direto à rede (sem cache)
//   - Imagens locais → cache-first (rápido)
//   - Quando há nova versão deste sw.js → activa e força refresh dos clientes

const CACHE_VERSION = 'fleetpay-v2-2026-05-04-mobile';
const CACHE_STATIC = `${CACHE_VERSION}-static`;
const CACHE_RUNTIME = `${CACHE_VERSION}-runtime`;

// Recursos críticos pré-cached
const PRECACHE_URLS = [
  '/',
  '/motorista.html',
  '/login.html',
  '/favicon.svg',
  '/manifest.json',
];

self.addEventListener('install', (event) => {
  console.log('[SW] install', CACHE_VERSION);
  event.waitUntil(
    caches.open(CACHE_STATIC).then((cache) => cache.addAll(PRECACHE_URLS).catch(() => {}))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  console.log('[SW] activate', CACHE_VERSION);
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k !== CACHE_STATIC && k !== CACHE_RUNTIME)
          .map((k) => {
            console.log('[SW] delete old cache:', k);
            return caches.delete(k);
          })
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;

  // Só GETs
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Skip cross-origin (Supabase, CDNs, fonts) — passa direto à rede
  if (url.origin !== self.location.origin) return;

  // HTML/JSON: network-first (apanha sempre versão nova quando online)
  const accept = req.headers.get('accept') || '';
  const isHTML = accept.includes('text/html') || url.pathname.endsWith('.html') || url.pathname === '/';
  const isJSON = url.pathname.endsWith('.json') || accept.includes('application/json');
  const isJS = url.pathname.endsWith('.js');

  if (isHTML || isJSON || isJS) {
    event.respondWith(networkFirst(req));
    return;
  }

  // Imagens, CSS, fonts: cache-first
  event.respondWith(cacheFirst(req));
});

async function networkFirst(req) {
  try {
    const fresh = await fetch(req);
    if (fresh && fresh.ok) {
      const cache = await caches.open(CACHE_RUNTIME);
      cache.put(req, fresh.clone()).catch(() => {});
    }
    return fresh;
  } catch (e) {
    const cached = await caches.match(req);
    if (cached) return cached;
    throw e;
  }
}

async function cacheFirst(req) {
  const cached = await caches.match(req);
  if (cached) return cached;
  try {
    const fresh = await fetch(req);
    if (fresh && fresh.ok) {
      const cache = await caches.open(CACHE_RUNTIME);
      cache.put(req, fresh.clone()).catch(() => {});
    }
    return fresh;
  } catch (e) {
    return new Response('Offline', { status: 503 });
  }
}

// Mensagens do app → SW (para forçar update)
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
