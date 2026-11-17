// ZORX app-shell service worker. build_web.py replaces the build id placeholder below, so every release changes this
// file's bytes and the browser installs the new worker.
//
// HARD RULE: this worker never stores the game. It caches ONLY offline.html, the manifest and the icons listed below.
// play.html, packs.json, index.js and the engine/pack .wasm files always go to the network, so a stale game build can
// never be served from here. Their freshness is still decided by nginx (no-cache / immutable hashed names).
// Navigations: network first; only if the network fails, show the tiny offline page.
const BUILD = '__BUILD_ID__';
const CACHE = 'zorx-shell-' + BUILD;
const SHELL = ['offline.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'icon-maskable-512.png', 'apple-touch-icon.png'];

self.addEventListener('install', function (event) {
  event.waitUntil(caches.open(CACHE).then(function (cache) {
    return Promise.all(SHELL.map(function (path) {
      return fetch(new Request(path, { cache: 'reload' })).then(function (res) { if (res.ok) return cache.put(path, res); });
    }));
  }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener('activate', function (event) {
  event.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (key) { return key !== CACHE; }).map(function (key) { return caches.delete(key); }));
  }).then(function () { return self.clients.claim(); }));
});

self.addEventListener('fetch', function (event) {
  if (event.request.mode !== 'navigate') return; // everything else: untouched, straight to the network
  event.respondWith(fetch(event.request).catch(function () {
    return caches.open(CACHE).then(function (cache) { return cache.match('offline.html'); }).then(function (res) {
      return res || new Response('Offline', { status: 503, headers: { 'Content-Type': 'text/plain' } });
    });
  }));
});
