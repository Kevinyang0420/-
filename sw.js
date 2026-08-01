// Service Worker — 杨御风：火星远征
// 页面 HTML 采用「网络优先」(每次拉取最新，离线才用缓存)，
// 静态资源(js/图片)采用「缓存优先」(快速启动 + 离线可玩)。
const CACHE = 'mars-warrior-v5';

const ASSETS = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  './js/util.js',
  './js/input.js',
  './js/audio.js',
  './js/entities.js',
  './js/levels.js',
  './js/render.js',
  './js/game.js'
];

// 安装：预缓存全部资源
self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting())
  );
});

// 激活：清理旧版本缓存
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// 取资源
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // 页面 HTML：网络优先，确保每次都拿到最新版（含新按钮/新关卡）
  const isNav =
    req.mode === 'navigate' ||
    url.pathname.endsWith('/') ||
    url.pathname.endsWith('index.html');
  if (isNav) {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then((h) => h || caches.match('./index.html')))
    );
    return;
  }

  // 静态资源：缓存优先，离线可玩
  e.respondWith(
    caches.match(req).then((hit) => {
      if (hit) return hit;
      return fetch(req)
        .then((res) => {
          if (res.ok && url.origin === self.location.origin) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy));
          }
          return res;
        })
        .catch(() => caches.match('./index.html'));
    })
  );
});
