/* Service Worker：**只做一件事 —— 让页面本身永远是最新的**。

   🚨 2026-08-15 事故：Kevin 把 App 加到主屏后一直报「没有 key」。
      线上页面明明已经带了手动输入框（回抓确认过），他手机上却是旧版 ——
      Safari 把 index.html 缓存住了，主屏那个独立容器尤其顽固。
      「我改好了」和「他看到的是改好的」是两件事，中间隔着缓存这一层。

   策略分两类，故意不一样：
     · index.html / manifest → **network-first**，网络能通就用新的，断网才用缓存
     · d/*.bin（加密内容）  → cache-first，它们只在重新加密时才变，而且很大
*/
const V = 'kb-v1';

self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k))))
    .then(() => self.clients.claim())));

self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (u.origin !== location.origin) return;
  const isData = /\/d\/.*\.bin$/.test(u.pathname);

  if (isData){
    e.respondWith(caches.open(V).then(c =>
      c.match(e.request).then(hit => hit || fetch(e.request).then(r => {
        if (r.ok) c.put(e.request, r.clone());
        return r;
      }))));
    return;
  }
  // 页面/清单/图标：先走网络，失败才回缓存
  e.respondWith(
    fetch(e.request).then(r => {
      if (r.ok) caches.open(V).then(c => c.put(e.request, r.clone()));
      return r;
    }).catch(() => caches.match(e.request)));
});
