// util.js - 通用工具函数（纯函数，无浏览器依赖）
// 画面内部分辨率（画布像素）；显示大小由 CSS 等比缩放
var VIEW = { W: 1440, H: 810 };

var Util = {
  clamp: function (v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); },
  lerp: function (a, b, t) { return a + (b - a) * t; },
  rand: function (a, b) { return a + Math.random() * (b - a); },
  randInt: function (a, b) { return Math.floor(a + Math.random() * (b - a + 1)); },
  choice: function (arr) { return arr[Math.floor(Math.random() * arr.length)]; },
  sign: function (v) { return v < 0 ? -1 : (v > 0 ? 1 : 0); },
  // 逐步逼近目标值，不超过 delta
  approach: function (v, target, delta) {
    if (v < target) return Math.min(v + delta, target);
    if (v > target) return Math.max(v - delta, target);
    return v;
  },
  // AABB 矩形重叠检测
  aabb: function (ax, ay, aw, ah, bx, by, bw, bh) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
  },
  // 距离平方
  dist2: function (ax, ay, bx, by) { var dx = ax - bx, dy = ay - by; return dx * dx + dy * dy; },
  // 圆角矩形路径（不绘制，仅建路径）
  roundRectPath: function (ctx, x, y, w, h, r) {
    if (w < 2 * r) r = w / 2;
    if (h < 2 * r) r = h / 2;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  },
  roundRect: function (ctx, x, y, w, h, r) {
    this.roundRectPath(ctx, x, y, w, h, r);
    ctx.fill();
  }
};
