// Offline-Cache für die Auswertung. Bei Änderungen die Version erhöhen.
const CACHE = 'wp-auswertung-2.6.0';
const DATEIEN = ['./', 'index.html', 'engine.js', 'manifest.webmanifest', 'icon.svg', 'icon-192.png', 'icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(DATEIEN))); self.skipWaiting(); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(k => Promise.all(k.filter(n => n !== CACHE).map(n => caches.delete(n)))));
  self.clients.claim();
});
// Erst Netz (aktuelle Version), bei fehlender Verbindung aus dem Cache
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(fetch(e.request).then(r => {
    const kopie = r.clone();
    caches.open(CACHE).then(c => c.put(e.request, kopie));
    return r;
  }).catch(() => caches.match(e.request)));
});
