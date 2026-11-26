// Tiene in memoria i file dell'app, così si apre anche senza rete (i dati restano su Supabase)
const CACHE = 'punzonatura-v2';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(k => Promise.all(k.filter(n => n.startsWith('punzonatura-') && n !== CACHE).map(n => caches.delete(n)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const r = e.request;
  const u = new URL(r.url);
  // i file del lettore foto sono gestiti dall'app nella sua cache dedicata
  if (r.method !== 'GET' || u.origin !== location.origin || u.pathname.includes('/ocr/')) return;
  e.respondWith(
    fetch(r).then(res => {
      if (res.ok) { const c = res.clone(); caches.open(CACHE).then(x => x.put(r, c)); }
      return res;
    }).catch(() => caches.match(r, { ignoreSearch: true }).then(m => m || (r.mode === 'navigate' ? caches.match('./') : undefined)))
  );
});
