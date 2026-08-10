const TAG = new URL(self.registration.scope).pathname;   // e.g. '/congruence75/'
const CACHE = 'c75' + TAG + '958f63e3da';
const ASSETS = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
});
self.addEventListener('message', e => {
  if (e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k !== CACHE && (k.startsWith('c75' + TAG) || k.startsWith('c75-')))
      .map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
// Photos live in their OWN cache, filled as he actually sees them. Precaching
// 35 MB at install would hammer his data for pictures he may never scroll to;
// this way each photo is downloaded once, ever, and is instant (and offline)
// from then on. The old handler fetched every photo from the network EVERY time
// because nothing wrote the response back into a cache.
const PHOTOS = 'c75photos' + TAG;
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin === self.location.origin && url.pathname.indexOf('/photos/') !== -1) {
    e.respondWith(caches.open(PHOTOS).then(c =>
      c.match(e.request).then(hit => hit || fetch(e.request).then(res => {
        if (res && res.ok) c.put(e.request, res.clone());
        return res;
      }).catch(() => hit))));
    return;
  }
  e.respondWith(caches.open(CACHE)
    .then(c => c.match(e.request, { ignoreSearch: true }))
    .then(r => r || fetch(e.request)));
});