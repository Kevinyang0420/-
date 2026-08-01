// render.js - 全部 Canvas 绘制（纯代码画，无外部图片）
// 《杨御风：火星远征》：主题 地球草地 / 太空 / 火星 / 城堡内部
var Render = {

  // ===== 文字 =====
  text: function (ctx, str, x, y, size, color, align, bold) {
    ctx.save();
    ctx.font = (bold ? 'bold ' : '') + size + "px 'Microsoft YaHei','PingFang SC','Segoe UI',sans-serif";
    ctx.textAlign = align || 'left';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = color || '#fff';
    if (ctx.fillText) ctx.fillText(str, x, y);
    ctx.restore();
  },

  strokeText: function (ctx, str, x, y, size, fill, stroke, sw) {
    ctx.save();
    ctx.font = "bold " + size + "px 'Microsoft YaHei','PingFang SC','Segoe UI',sans-serif";
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = sw || 6;
    ctx.strokeStyle = stroke || '#000';
    ctx.lineJoin = 'round';
    if (ctx.strokeText) ctx.strokeText(str, x, y);
    ctx.fillStyle = fill || '#fff';
    if (ctx.fillText) ctx.fillText(str, x, y);
    ctx.restore();
  },

  // ===== 背景 =====
  background: function (ctx, stage, cam, t, stars, opts) {
    opts = opts || {};
    var W = VIEW.W, H = VIEW.H;
    var theme = opts.themeOverride || stage.theme;

    if (theme === 'earth') {
      this._earthSky(ctx, W, H, cam, t, stars, opts.blend || 0);
    } else if (theme === 'space') {
      this._spaceSky(ctx, W, H, cam, t, stars);
    } else if (theme === 'mars') {
      this._marsSky(ctx, W, H, cam, t, stars);
    } else if (theme === 'moon') {
      this._moonSky(ctx, W, H, cam, t, stars);
    } else {
      this._castleSky(ctx, W, H, cam, t);
    }
    this._ground(ctx, stage, cam, theme, t, opts);
  },

  // 地球：蓝天 + 太阳 + 白云；blend>0 时（火箭发射过场）天空渐变为太空、星星渐现
  _earthSky: function (ctx, W, H, cam, t, stars, blend) {
    var b = blend || 0;
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, this._mix('#6fb6ff', '#070a1f', b));
    g.addColorStop(1, this._mix('#cfeaff', '#1a1f3a', b));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);

    // 星空渐现
    if (stars && b > 0) {
      for (var si = 0; si < stars.length; si++) {
        var st = stars[si];
        var stx = ((st.x - cam.x * 0.25) % W + W) % W;
        var tw = 0.5 + 0.5 * Math.sin(t * 2 + st.ph);
        ctx.globalAlpha = b * (0.4 + 0.6 * tw);
        ctx.fillStyle = st.big ? '#cfe0ff' : '#ffffff';
        ctx.fillRect(stx, st.y, st.big ? 3.75 : 2.25, st.big ? 3.75 : 2.25);
      }
      ctx.globalAlpha = 1;
    }

    // 太阳与白云（发射时淡出）
    ctx.save();
    ctx.globalAlpha = 1 - b;
    ctx.fillStyle = 'rgba(255,255,210,0.7)';
    ctx.beginPath(); ctx.arc(1230 - cam.x * 0.15, 135, 75, 0, Math.PI * 2); ctx.fill();
    var off = (t * 18) % 1800;
    this._cloud(ctx, ((300 - off) % 1800 + 1800) % 1800, 180);
    this._cloud(ctx, ((840 - off * 0.7) % 1800 + 1800) % 1800, 300);
    this._cloud(ctx, ((1350 - off * 1.3) % 1800 + 1800) % 1800, 135);
    ctx.restore();
  },

  // 太空：深邃星空 + 远处的地球和火星
  _spaceSky: function (ctx, W, H, cam, t, stars) {
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#070a1f');
    g.addColorStop(1, '#1a1f3a');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    this._stars(ctx, W, cam, t, stars);
    this._earthFar(ctx, 210 - cam.x * 0.1, 165);
    // 远处小小的火星（红色）
    var mx = 1180 - cam.x * 0.12, my = 240;
    ctx.fillStyle = '#c85a3a';
    ctx.beginPath(); ctx.arc(mx, my, 34, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#a8442c';
    ctx.beginPath(); ctx.arc(mx - 8, my - 6, 12, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(mx + 10, my + 10, 9, 0, Math.PI * 2); ctx.fill();
  },

  // 火星：暗红天空 + 稀疏星星 + 远处红色山丘
  _marsSky: function (ctx, W, H, cam, t, stars) {
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#2a1420');
    g.addColorStop(0.6, '#5a2430');
    g.addColorStop(1, '#8a3a30');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    // 稀疏暗星
    if (stars) {
      for (var i = 0; i < stars.length; i += 2) {
        var s = stars[i];
        var sx = ((s.x - cam.x * 0.25) % W + W) % W;
        ctx.globalAlpha = 0.25 + 0.3 * (0.5 + 0.5 * Math.sin(t * 2 + s.ph));
        ctx.fillStyle = '#ffd8c8';
        ctx.fillRect(sx, s.y, 2.25, 2.25);
      }
      ctx.globalAlpha = 1;
    }
    // 远处红色山丘剪影（视差 0.3 / 0.5）
    this._marsHills(ctx, cam.x * 0.3, H, '#7e3226', 600, 105);
    this._marsHills(ctx, cam.x * 0.5, H, '#9c4229', 660, 67);
    // 天上挂着的地球（家！）
    this._earthFar(ctx, 1130 - cam.x * 0.08, 150);
  },

  _marsHills: function (ctx, off, H, color, baseY, amp) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(0, H);
    for (var x = 0; x <= VIEW.W; x += 30) {
      var wx = x + (off % 480);
      var y = baseY + Math.sin(wx * 0.006) * amp + Math.sin(wx * 0.017) * amp * 0.4;
      ctx.lineTo(x, y);
    }
    ctx.lineTo(VIEW.W, H);
    ctx.closePath();
    ctx.fill();
  },

  // 神秘城堡内部：深色石墙 + 拱形窗透出暖光 + 墙上火把微微摇晃
  _castleSky: function (ctx, W, H, cam, t) {
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#14101e');
    g.addColorStop(1, '#2c2438');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);

    // 石墙砖缝（按世界坐标平铺，弱视差）
    ctx.strokeStyle = 'rgba(0,0,0,0.28)';
    ctx.lineWidth = 3;
    var rowH = 54;
    for (var ry = 40; ry < 640; ry += rowH) {
      ctx.beginPath(); ctx.moveTo(0, ry); ctx.lineTo(W, ry); ctx.stroke();
      var off = (Math.floor(ry / rowH) % 2) * 60;
      var startX = Math.floor((cam.x * 0.6) / 120) * 120 - 240;
      for (var wx = startX; wx < cam.x * 0.6 + W + 240; wx += 120) {
        var sx = wx - cam.x * 0.6 + off;
        ctx.beginPath(); ctx.moveTo(sx, ry); ctx.lineTo(sx, ry + rowH); ctx.stroke();
      }
    }

    // 拱形窗（透出外面的紫红色天光）
    var wSpacing = 480;
    var wStart = Math.floor(cam.x * 0.7 / wSpacing) * wSpacing;
    for (var wx2 = wStart; wx2 < cam.x * 0.7 + W + wSpacing; wx2 += wSpacing) {
      var sx2 = wx2 - cam.x * 0.7 + 120;
      // 窗洞
      ctx.fillStyle = '#4a2c40';
      ctx.beginPath();
      ctx.moveTo(sx2 - 45, 330);
      ctx.lineTo(sx2 - 45, 190);
      ctx.arc(sx2, 190, 45, Math.PI, 0);
      ctx.lineTo(sx2 + 45, 330);
      ctx.closePath(); ctx.fill();
      // 窗外天光
      var wg = ctx.createLinearGradient(0, 150, 0, 330);
      wg.addColorStop(0, '#8a4a5a');
      wg.addColorStop(1, '#3a2438');
      ctx.fillStyle = wg;
      ctx.beginPath();
      ctx.moveTo(sx2 - 36, 322);
      ctx.lineTo(sx2 - 36, 192);
      ctx.arc(sx2, 192, 36, Math.PI, 0);
      ctx.lineTo(sx2 + 36, 322);
      ctx.closePath(); ctx.fill();
      // 窗棂
      ctx.strokeStyle = '#2a1c28';
      ctx.lineWidth = 5;
      ctx.beginPath(); ctx.moveTo(sx2, 158); ctx.lineTo(sx2, 322); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(sx2 - 36, 240); ctx.lineTo(sx2 + 36, 240); ctx.stroke();
    }

    // 火把：火苗一晃一晃
    var tSpacing = 360;
    var tStart = Math.floor(cam.x * 0.85 / tSpacing) * tSpacing;
    for (var wx3 = tStart; wx3 < cam.x * 0.85 + W + tSpacing; wx3 += tSpacing) {
      var sx3 = wx3 - cam.x * 0.85 + 60;
      var flick = Math.sin(t * 9 + wx3) * 3 + Math.sin(t * 23 + wx3 * 2) * 1.5;
      // 光晕
      ctx.globalAlpha = 0.10 + 0.03 * Math.sin(t * 7 + wx3);
      ctx.fillStyle = '#ffb040';
      ctx.beginPath(); ctx.arc(sx3, 420, 90, 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = 1;
      // 火把杆
      ctx.fillStyle = '#5a4030';
      ctx.fillRect(sx3 - 4, 420, 8, 40);
      // 火苗
      ctx.fillStyle = '#ff8a2a';
      ctx.beginPath();
      ctx.moveTo(sx3, 396 - 26 - flick);
      ctx.bezierCurveTo(sx3 + 12, 396 - 6, sx3 + 8, 396 + 8, sx3, 396 + 8);
      ctx.bezierCurveTo(sx3 - 8, 396 + 8, sx3 - 12, 396 - 6, sx3, 396 - 26 - flick);
      ctx.fill();
      ctx.fillStyle = '#ffd94a';
      ctx.beginPath();
      ctx.moveTo(sx3, 396 - 12 - flick * 0.6);
      ctx.bezierCurveTo(sx3 + 6, 396, sx3 + 4, 396 + 6, sx3, 396 + 6);
      ctx.bezierCurveTo(sx3 - 4, 396 + 6, sx3 - 6, 396, sx3, 396 - 12 - flick * 0.6);
      ctx.fill();
    }
  },

  // 月球：深空 + 星星 + 远处巨大的地球（回家的方向）+ 环形山远景剪影
  _moonSky: function (ctx, W, H, cam, t, stars) {
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#05060f');
    g.addColorStop(0.6, '#0c1024');
    g.addColorStop(1, '#1a2138');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    this._stars(ctx, W, cam, t, stars);
    // 远处巨大的地球
    this._earthFar(ctx, 1180 - cam.x * 0.06, 150);
    // 环形山远景剪影（视差）
    ctx.fillStyle = '#2a2f44';
    ctx.beginPath();
    ctx.moveTo(0, H);
    for (var mx = 0; mx <= W; mx += 40) {
      var wx = mx + (cam.x * 0.2 % 320);
      var wy = 565 + Math.sin(wx * 0.01) * 38 + Math.sin(wx * 0.03) * 16;
      ctx.lineTo(mx, wy);
    }
    ctx.lineTo(W, H); ctx.closePath(); ctx.fill();
  },

  _stars: function (ctx, W, cam, t, stars) {
    if (!stars) return;
    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var sx = ((s.x - cam.x * 0.25) % W + W) % W;
      var tw = 0.5 + 0.5 * Math.sin(t * 2 + s.ph);
      ctx.globalAlpha = 0.4 + 0.6 * tw;
      ctx.fillStyle = s.big ? '#cfe0ff' : '#ffffff';
      ctx.fillRect(sx, s.y, s.big ? 3.75 : 2.25, s.big ? 3.75 : 2.25);
    }
    ctx.globalAlpha = 1;
  },

  // 远处地球
  _earthFar: function (ctx, ex, ey) {
    ctx.fillStyle = '#2a6fd6';
    ctx.beginPath(); ctx.arc(ex, ey, 51, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#3aa856';
    ctx.beginPath(); ctx.arc(ex - 12, ey - 9, 18, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex + 15, ey + 12, 13.5, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.25)';
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(ex, ey, 51, 0, Math.PI * 2); ctx.stroke();
  },

  _cloud: function (ctx, x, y) {
    ctx.fillStyle = 'rgba(255,255,255,0.9)';
    ctx.beginPath();
    ctx.arc(x, y, 33, 0, Math.PI * 2);
    ctx.arc(x + 36, y + 6, 27, 0, Math.PI * 2);
    ctx.arc(x - 33, y + 6, 24, 0, Math.PI * 2);
    ctx.arc(x, y + 15, 36, 0, Math.PI * 2);
    ctx.fill();
  },

  _ground: function (ctx, stage, cam, theme, t, opts) {
    var W = VIEW.W, H = VIEW.H, gy = stage.groundY;
    var top, edge, dark;
    if (theme === 'earth') { top = '#5fbf4a'; edge = '#3a9a32'; dark = '#2e7d28'; }
    else if (theme === 'mars') { top = '#c85a3a'; edge = '#a03e26'; dark = '#7e2e1c'; }
    else if (theme === 'castle') { top = '#6a6478'; edge = '#4e4858'; dark = '#3a3442'; }
    else if (theme === 'moon') { top = '#9a93a0'; edge = '#74707e'; dark = '#56525e'; }
    else { top = '#8d93a6'; edge = '#6e7386'; dark = '#565b6e'; }   // space 小行星岩石

    ctx.fillStyle = edge;
    ctx.fillRect(0, gy, W, H - gy);
    ctx.fillStyle = top;
    ctx.fillRect(0, gy, W, 15);

    // 地面装饰按世界坐标平铺
    var spacing = 135;
    var startX = Math.floor(cam.x / spacing) * spacing;
    for (var wx = startX; wx < cam.x + W + spacing; wx += spacing) {
      var sx = wx - cam.x;
      var seed = (wx * 0.0137) % 1;
      if (theme === 'space' || theme === 'mars' || theme === 'moon') {
        // 环形山 + 小石块
        var r = 15 + Math.abs(Math.sin(wx * 0.7)) * 21;
        ctx.fillStyle = dark;
        ctx.beginPath();
        ctx.ellipse(sx + 30, gy + 33, r, r * 0.5, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = edge;
        ctx.beginPath();
        ctx.ellipse(sx + 24, gy + 30, r * 0.6, r * 0.3, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = dark;
        ctx.fillRect(sx + 90, gy + 42, 10, 7);
      } else if (theme === 'castle') {
        // 石板地：砖缝 + 零星裂纹
        ctx.fillStyle = dark;
        ctx.fillRect(sx + 20, gy + 15, 4, 30);
        ctx.fillRect(sx + 78, gy + 15, 4, 30);
        ctx.fillRect(sx, gy + 44, 135, 4);
        ctx.fillRect(sx + (seed * 60), gy + 60, 12, 5);
      } else {
        // 草丛
        ctx.fillStyle = dark;
        ctx.fillRect(sx + 15, gy + 9, 4.5, 12);
        ctx.fillRect(sx + 21, gy + 6, 4.5, 15);
        ctx.fillRect(sx + 27, gy + 9, 4.5, 12);
      }
    }
  },

  _mix: function (c1, c2, t) {
    var a = this._hex(c1), b = this._hex(c2);
    var r = Math.round(a[0] + (b[0] - a[0]) * t);
    var g = Math.round(a[1] + (b[1] - a[1]) * t);
    var bl = Math.round(a[2] + (b[2] - a[2]) * t);
    return 'rgb(' + r + ',' + g + ',' + bl + ')';
  },
  _hex: function (h) {
    h = h.replace('#', '');
    return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
  },

  // ===== 平台 =====
  platform: function (ctx, p, cam, theme) {
    var x = p.x - cam.x, y = p.y;
    var top, side;
    if (theme === 'earth') { top = '#7ad06a'; side = '#3a9a32'; }
    else if (theme === 'mars') { top = '#d8784a'; side = '#8a3a24'; }
    else if (theme === 'castle') { top = '#8a8498'; side = '#544e60'; }
    else if (theme === 'moon') { top = '#cfcad8'; side = '#8e889a'; }
    else { top = '#b8bdc8'; side = '#888e9a'; }
    ctx.fillStyle = side;
    Util.roundRect(ctx, x, y, p.w, p.h, 9);
    ctx.fillStyle = top;
    Util.roundRect(ctx, x, y, p.w, 9, 6);
  },

  // ===== 杨御风（太空战士：蓝红战甲 + 透明头盔）=====
  player: function (ctx, p, cam) {
    if (p.invincible > 0 && Math.floor(p.invincible * 18) % 2 === 0) return; // 无敌闪烁
    var x = p.x - cam.x, y = p.y;
    var cx = x + p.w / 2;
    var moving = p.onGround && Math.abs(p.vx) > 0.6;
    var swing = moving ? Math.sin(p.anim) : 0;

    ctx.save();
    // 背包（蓝色喷气背包）
    ctx.fillStyle = '#2a3f8f';
    Util.roundRect(ctx, x + (p.facing < 0 ? 18 : 3), y + 24, 18, 33, 6);
    ctx.fillStyle = '#5a7ae0';
    ctx.fillRect(x + (p.facing < 0 ? 21 : 6), y + 30, 12, 4.5);
    // 腿（深蓝战甲，跑动摆动）
    ctx.fillStyle = '#2a3f8f';
    ctx.fillRect(x + 9 + swing * 4.5, y + 51, 9, 13.5);
    ctx.fillRect(x + 21 - swing * 4.5, y + 51, 9, 13.5);
    // 战靴（红色）
    ctx.fillStyle = '#d93a3a';
    ctx.fillRect(x + 7.5 + swing * 4.5, y + 61.5, 12, 4.5);
    ctx.fillRect(x + 19.5 - swing * 4.5, y + 61.5, 12, 4.5);
    // 身体（蓝色战甲）
    ctx.fillStyle = '#3a5fd9';
    Util.roundRect(ctx, x + 6, y + 24, 27, 30, 9);
    // 红色胸甲
    ctx.fillStyle = '#d93a3a';
    ctx.fillRect(x + 13, y + 31, 13, 10);
    ctx.fillStyle = '#ffd94a';
    ctx.fillRect(x + 17, y + 34, 5, 4);
    // 手臂（蓝色，红色护腕）
    ctx.fillStyle = '#3a5fd9';
    ctx.fillRect(x + 1.5, y + 27 - swing * 3, 7.5, 18);
    ctx.fillRect(x + 30, y + 27 + swing * 3, 7.5, 18);
    ctx.fillStyle = '#d93a3a';
    ctx.fillRect(x + 1.5, y + 41 - swing * 3, 7.5, 5);
    ctx.fillRect(x + 30, y + 41 + swing * 3, 7.5, 5);
    // 脸（透过透明头盔能看到）
    ctx.fillStyle = '#f0c8a0';
    ctx.beginPath();
    ctx.arc(cx, y + 15, 12, 0, Math.PI * 2);
    ctx.fill();
    // 眼睛（看向移动方向）
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(cx - 4 + p.facing * 2, y + 13, 2, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 4 + p.facing * 2, y + 13, 2, 0, Math.PI * 2); ctx.fill();
    // 微笑
    ctx.strokeStyle = '#8a5a3a';
    ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.arc(cx + p.facing, y + 18, 4, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    // 透明头盔（玻璃罩 + 描边 + 高光）
    ctx.fillStyle = 'rgba(180,230,255,0.28)';
    ctx.beginPath();
    ctx.arc(cx, y + 15, 18, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#9ac8e8';
    ctx.lineWidth = 2.25;
    ctx.stroke();
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ctx.beginPath();
    ctx.ellipse(cx - 7, y + 6, 4.5, 2.5, -0.6, 0, Math.PI * 2);
    ctx.fill();
    // 头盔两侧红色护耳 + 天线
    ctx.fillStyle = '#d93a3a';
    ctx.beginPath(); ctx.arc(cx - 16, y + 16, 4, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 16, y + 16, 4, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = '#9ac8e8';
    ctx.lineWidth = 2.25;
    ctx.beginPath();
    ctx.moveTo(cx, y - 1.5);
    ctx.lineTo(cx, y - 10.5);
    ctx.stroke();
    ctx.fillStyle = '#ff5252';
    ctx.beginPath();
    ctx.arc(cx, y - 12, 3, 0, Math.PI * 2);
    ctx.fill();
    // 晕眩：头顶转圈的小星星
    if (p.dizzyT > 0) {
      ctx.fillStyle = '#ffe14a';
      for (var i = 0; i < 3; i++) {
        var a = p.anim * 0.8 + i * 2.09;
        ctx.beginPath();
        ctx.arc(cx + Math.cos(a) * 22, y - 8 + Math.sin(a) * 7, 3.5, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.restore();
  },

  // ===== 雪球 =====
  snowball: function (ctx, s, cam) {
    var x = s.x - cam.x + s.r, y = s.y + s.r;
    ctx.save();
    // 阴影
    ctx.fillStyle = 'rgba(0,0,0,0.15)';
    ctx.beginPath();
    ctx.ellipse(x, s.y + s.r * 2 + 6, s.r * 0.8, s.r * 0.3, 0, 0, Math.PI * 2);
    ctx.fill();
    // 球体
    var g = ctx.createRadialGradient(x - s.r * 0.3, y - s.r * 0.3, s.r * 0.2, x, y, s.r);
    g.addColorStop(0, '#ffffff');
    g.addColorStop(1, '#c8d2e0');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, s.r, 0, Math.PI * 2);
    ctx.fill();
    // 滚动纹理（旋转的小块）
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(s.spin);
    ctx.fillStyle = 'rgba(120,140,170,0.5)';
    for (var i = 0; i < 6; i++) {
      var a = (i / 6) * Math.PI * 2;
      var rr = s.r * 0.55;
      ctx.beginPath();
      ctx.arc(Math.cos(a) * rr, Math.sin(a) * rr, s.r * 0.12, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
    ctx.restore();
  },

  // ===== 房子（从天上砸下来的卡通小房子；地上的影子提醒小朋友快躲开）=====
  house: function (ctx, e, cam, groundY) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    ctx.save();
    // 落点影子（越接近地面影子越大越深）
    if (groundY) {
      var prog = Util.clamp((y + e.h) / groundY, 0, 1);
      ctx.globalAlpha = 0.12 + 0.22 * prog;
      ctx.fillStyle = '#000';
      ctx.beginPath();
      ctx.ellipse(cx, groundY + 8, 30 + 26 * prog, 7 + 4 * prog, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
    // 下落时轻轻摇晃
    ctx.translate(cx, y + e.h / 2);
    ctx.rotate(Math.sin(e.wob) * 0.08);
    ctx.translate(-cx, -(y + e.h / 2));
    // 烟囱
    ctx.fillStyle = '#a05a4a';
    ctx.fillRect(x + 66, y + 6, 14, 22);
    // 屋顶（大红三角）
    ctx.fillStyle = '#c84a3a';
    ctx.beginPath();
    ctx.moveTo(x - 4, y + 36);
    ctx.lineTo(cx, y + 2);
    ctx.lineTo(x + e.w + 4, y + 36);
    ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#a83828';
    ctx.fillRect(x - 4, y + 32, e.w + 8, 7);
    // 墙
    ctx.fillStyle = '#e8d0a0';
    ctx.fillRect(x + 8, y + 39, e.w - 16, e.h - 39);
    // 门
    ctx.fillStyle = '#7a4a2a';
    Util.roundRect(ctx, cx - 11, y + 54, 22, 30, 6);
    ctx.fillStyle = '#ffd94a';
    ctx.beginPath(); ctx.arc(cx + 6, y + 70, 2.5, 0, Math.PI * 2); ctx.fill();
    // 窗户
    ctx.fillStyle = '#7ab8e0';
    ctx.fillRect(x + 16, y + 48, 16, 14);
    ctx.fillRect(x + 64, y + 48, 16, 14);
    ctx.strokeStyle = '#5a8ab0';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(x + 24, y + 48); ctx.lineTo(x + 24, y + 62); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x + 72, y + 48); ctx.lineTo(x + 72, y + 62); ctx.stroke();
    ctx.restore();
  },

  // ===== 大便兽 =====
  poopbeast: function (ctx, b, cam) {
    var x = b.x - cam.x + b.w / 2, y = b.y;
    var squash = b.deadT > 0 ? Math.max(0.1, 1 - b.deadT * 4) : 1;
    ctx.save();
    ctx.translate(x, y + b.h);
    ctx.scale(1, squash);
    ctx.translate(-x, -(y + b.h));

    var layers = [
      { dx: 0, dy: 36, rx: 33, ry: 18, c: '#6b3f1c' },
      { dx: 0, dy: 21, rx: 27, ry: 16.5, c: '#7a4a22' },
      { dx: 0, dy: 7.5, rx: 21, ry: 15, c: '#8a5528' },
      { dx: 0, dy: -4.5, rx: 15, ry: 12, c: '#9a6230' }
    ];
    for (var i = 0; i < layers.length; i++) {
      var L = layers[i];
      ctx.fillStyle = L.c;
      ctx.beginPath();
      ctx.ellipse(x + L.dx, y + L.dy, L.rx, L.ry, 0, 0, Math.PI * 2);
      ctx.fill();
      // 螺旋纹
      ctx.strokeStyle = 'rgba(60,30,10,0.5)';
      ctx.lineWidth = 2.25;
      ctx.beginPath();
      ctx.ellipse(x + L.dx, y + L.dy, L.rx * 0.7, L.ry * 0.7, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
    // 大眼睛
    var look = Util.sign(b.vx) || 1;
    ctx.fillStyle = '#ffffff';
    ctx.beginPath(); ctx.arc(x - 9, y + 3, 9, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 9, y + 3, 9, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(x - 9 + look * 2.25, y + 4.5, 3.9, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 9 + look * 2.25, y + 4.5, 3.9, 0, Math.PI * 2); ctx.fill();
    // 嘴（傻笑）
    ctx.strokeStyle = '#3a1f0a';
    ctx.lineWidth = 2.25;
    ctx.beginPath();
    ctx.arc(x, y + 13.5, 6, 0.1 * Math.PI, 0.9 * Math.PI);
    ctx.stroke();
    // 腮红
    ctx.fillStyle = 'rgba(255,120,120,0.5)';
    ctx.beginPath(); ctx.arc(x - 16.5, y + 9, 3.75, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 16.5, y + 9, 3.75, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  },

  // ===== 长角兽（头长两只大角的橙红色小兽）=====
  hornbeast: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var squash = e.deadT > 0 ? Math.max(0.1, 1 - e.deadT * 4) : 1;
    ctx.save();
    ctx.translate(cx, y + e.h);
    ctx.scale(Math.min(1.6, 1 / Math.sqrt(squash)), squash);
    ctx.translate(-cx, -(y + e.h));
    var dir = e.dir || 1;
    // 小短腿（走路摆动）
    var step = Math.sin(e.anim) * 3;
    ctx.fillStyle = '#a84a1a';
    ctx.fillRect(x + 10 + step, y + e.h - 8, 9, 8);
    ctx.fillRect(x + e.w - 19 - step, y + e.h - 8, 9, 8);
    // 圆滚滚的身体
    var g = ctx.createLinearGradient(0, y, 0, y + e.h);
    g.addColorStop(0, '#f08838');
    g.addColorStop(1, '#d05a20');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.ellipse(cx, y + 26, 26, 22, 0, 0, Math.PI * 2); ctx.fill();
    // 肚皮
    ctx.fillStyle = '#f8b060';
    ctx.beginPath(); ctx.ellipse(cx, y + 34, 15, 11, 0, 0, Math.PI * 2); ctx.fill();
    // 两只大白角（弯弯的）
    ctx.fillStyle = '#fff2d8';
    ctx.beginPath();
    ctx.moveTo(cx - 14, y + 12);
    ctx.bezierCurveTo(cx - 26, y + 8, cx - 30, y - 6, cx - 25, y - 13);
    ctx.bezierCurveTo(cx - 22, y - 4, cx - 16, y + 2, cx - 8, y + 6);
    ctx.closePath(); ctx.fill();
    ctx.beginPath();
    ctx.moveTo(cx + 14, y + 12);
    ctx.bezierCurveTo(cx + 26, y + 8, cx + 30, y - 6, cx + 25, y - 13);
    ctx.bezierCurveTo(cx + 22, y - 4, cx + 16, y + 2, cx + 8, y + 6);
    ctx.closePath(); ctx.fill();
    // 凶凶的眼睛（其实不可怕）
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(cx - 8, y + 20, 6, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 8, y + 20, 6, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(cx - 8 + dir * 2, y + 21, 2.8, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 8 + dir * 2, y + 21, 2.8, 0, Math.PI * 2); ctx.fill();
    // 倒八字眉
    ctx.strokeStyle = '#7a2a10';
    ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.moveTo(cx - 13, y + 12); ctx.lineTo(cx - 4, y + 16); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx + 13, y + 12); ctx.lineTo(cx + 4, y + 16); ctx.stroke();
    // 咧嘴
    ctx.strokeStyle = '#7a2a10';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(cx, y + 29, 6, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    ctx.restore();
  },

  // ===== 滚球兽（缩成带刺的球一路滚来）=====
  rollbeast: function (ctx, e, cam) {
    var x = e.x - cam.x + e.r, y = e.y + e.r;
    var squash = e.deadT > 0 ? Math.max(0.1, 1 - e.deadT * 4) : 1;
    ctx.save();
    ctx.translate(x, e.y + e.h);
    ctx.scale(Math.min(1.5, 1 / Math.sqrt(squash)), squash);
    ctx.translate(-x, -(e.y + e.h));
    // 阴影
    ctx.fillStyle = 'rgba(0,0,0,0.15)';
    ctx.beginPath();
    ctx.ellipse(x, e.y + e.h + 5, e.r * 0.8, e.r * 0.25, 0, 0, Math.PI * 2);
    ctx.fill();
    // 球体
    var g = ctx.createRadialGradient(x - 8, y - 8, 4, x, y, e.r);
    g.addColorStop(0, '#5ac8be');
    g.addColorStop(1, '#2a8a82');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.fill();
    // 尖刺（随滚动旋转）
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(e.spin);
    ctx.fillStyle = '#1a6a64';
    for (var i = 0; i < 8; i++) {
      var a = (i / 8) * Math.PI * 2;
      var sx = Math.cos(a), sy = Math.sin(a);
      ctx.beginPath();
      ctx.moveTo(sx * (e.r - 4) - sy * 5, sy * (e.r - 4) + sx * 5);
      ctx.lineTo(sx * (e.r + 9), sy * (e.r + 9));
      ctx.lineTo(sx * (e.r - 4) + sy * 5, sy * (e.r - 4) - sx * 5);
      ctx.closePath(); ctx.fill();
    }
    ctx.restore();
    // 一只大眼睛（不旋转，盯住玩家）
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(x, y - 2, 9, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(x + Util.sign(e.vx) * 2.5, y - 1, 4, 0, Math.PI * 2); ctx.fill();
    // 嘴
    ctx.strokeStyle = '#134a46';
    ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.arc(x, y + 9, 6, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    ctx.restore();
  },

  // ===== 鼻涕虫（贴地慢慢爬的小虫）=====
  snotworm: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var squash = e.deadT > 0 ? Math.max(0.1, 1 - e.deadT * 4) : 1;
    ctx.save();
    ctx.translate(x + e.w / 2, y + e.h);
    ctx.scale(1, squash);
    ctx.translate(-(x + e.w / 2), -(y + e.h));
    var dir = Util.sign(e.vx) || 1;
    // 三节身体（爬行时一拱一拱）
    for (var i = 0; i < 3; i++) {
      var segX = x + 10 + i * 12;
      var wob = Math.sin(e.anim + i * 1.2) * 3;
      ctx.fillStyle = i === 2 ? '#c8e058' : '#a8c84a';
      ctx.beginPath();
      ctx.ellipse(segX, y + e.h - 9 - wob * 0.5, 9, 9 - wob * 0.3, 0, 0, Math.PI * 2);
      ctx.fill();
    }
    // 头（在移动方向那一端）
    var hx = dir > 0 ? x + 34 : x + 10;
    ctx.fillStyle = '#c8e058';
    ctx.beginPath(); ctx.arc(hx, y + e.h - 12, 8, 0, Math.PI * 2); ctx.fill();
    // 眼睛
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(hx + dir * 3, y + e.h - 15, 3.5, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(hx + dir * 4, y + e.h - 14.5, 1.8, 0, Math.PI * 2); ctx.fill();
    // 小触角
    ctx.strokeStyle = '#7a9a2a';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(hx + dir * 2, y + e.h - 19);
    ctx.lineTo(hx + dir * 5, y + e.h - 24 + Math.sin(e.anim * 2) * 2);
    ctx.stroke();
    ctx.restore();
  },

  // ===== 鼻涕兽 =====
  snotbeast: function (ctx, e, cam) {
    var x = e.x - cam.x + e.w / 2, yb = e.y + e.h;   // 底部中心
    var squash = e.deadT > 0 ? Math.max(0.1, 1 - e.deadT * 4) : 1;
    var br = 1 + Math.sin(e.breathe) * 0.07;         // 一鼓一瘪地呼吸
    ctx.save();
    ctx.translate(x, yb);
    ctx.scale(1 - (br - 1) * 0.8, br * squash);
    ctx.translate(-x, -yb);

    // 身后拖着的黏液尾巴
    ctx.fillStyle = 'rgba(168,216,74,0.55)';
    ctx.beginPath();
    ctx.ellipse(x - (e.facing || 1) * 40, yb - 6, 30, 9, 0, 0, Math.PI * 2);
    ctx.fill();
    // 身体（黄绿色半透明一坨）
    ctx.fillStyle = 'rgba(184,217,74,0.88)';
    ctx.beginPath(); ctx.ellipse(x, yb - 24, 33, 24, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(150,190,50,0.9)';
    ctx.beginPath(); ctx.ellipse(x, yb - 10, 30, 12, 0, 0, Math.PI * 2); ctx.fill();
    // 高光
    ctx.fillStyle = 'rgba(230,255,160,0.7)';
    ctx.beginPath(); ctx.ellipse(x - 10, yb - 32, 8, 5, -0.4, 0, Math.PI * 2); ctx.fill();
    // 滴下来的黏液
    ctx.fillStyle = 'rgba(184,217,74,0.8)';
    ctx.fillRect(x - 24, yb - 18, 6, 12 + Math.sin(e.breathe) * 3);
    ctx.fillRect(x + 18, yb - 15, 5, 9);
    // 眼柄 + 两个小眼睛
    var look = e.facing || 1;
    ctx.strokeStyle = '#7a9a2a';
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(x - 9, yb - 44); ctx.lineTo(x - 10, yb - 54); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x + 9, yb - 44); ctx.lineTo(x + 10, yb - 54); ctx.stroke();
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(x - 10, yb - 57, 7, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 10, yb - 57, 7, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(x - 10 + look * 2.5, yb - 56, 3, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 10 + look * 2.5, yb - 56, 3, 0, Math.PI * 2); ctx.fill();
    // 嘟嘴（吐鼻涕的嘴）
    ctx.fillStyle = '#7a9a2a';
    ctx.beginPath(); ctx.arc(x + look * 6, yb - 30, 4, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  },

  // ===== 鼻涕球 =====
  snotball: function (ctx, e, cam) {
    var x = e.x - cam.x + e.r, y = e.y + e.r;
    ctx.save();
    ctx.fillStyle = 'rgba(184,217,74,0.92)';
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(150,190,50,0.9)';
    ctx.beginPath(); ctx.arc(x + Math.cos(e.spin) * 4, y + 3, e.r * 0.55, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(235,255,170,0.85)';
    ctx.beginPath(); ctx.arc(x - 3, y - 4, 3.5, 0, Math.PI * 2); ctx.fill();
    // 拖尾小滴
    ctx.fillStyle = 'rgba(184,217,74,0.6)';
    ctx.beginPath(); ctx.arc(x - Util.sign(e.vx) * (e.r + 4), y + 2, 3, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  },

  // ===== 黏液 =====
  slime: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var a = e.maxLife > 100 ? 1 : Math.min(1, e.life / 1.2);   // 快消失时变淡
    ctx.save();
    ctx.globalAlpha = 0.85 * a;
    ctx.fillStyle = '#8ecf3e';
    ctx.beginPath(); ctx.ellipse(x + 45, y + 7, 45, 8, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#b8e060';
    ctx.beginPath(); ctx.ellipse(x + 38, y + 5, 26, 5, 0, 0, Math.PI * 2); ctx.fill();
    // 咕嘟咕嘟的泡
    ctx.fillStyle = '#d8f498';
    for (var i = 0; i < 3; i++) {
      var ph = (e.bubble * 1.5 + i * 0.7) % 1.5;
      ctx.beginPath();
      ctx.arc(x + 18 + i * 24, y + 6 - ph * 6, 2 + ph * 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  },

  // ===== 臭袜子兽 =====
  sockbeast: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    // 蹦跳拉伸：空中拉长、被踩压扁
    var squash = 1;
    if (e.deadT > 0) squash = Math.max(0.1, 1 - e.deadT * 4);
    else if (!e.onGround) squash = 1.08;
    ctx.save();
    ctx.translate(cx, y + e.h);
    ctx.scale(Math.min(1.6, 1 / Math.sqrt(squash)), squash);
    ctx.translate(-cx, -(y + e.h));

    var dir = e.dir || 1;
    // 袜身（灰蓝色长袜，袜口朝上，袜尖朝移动方向）
    ctx.fillStyle = '#7d8fae';
    ctx.beginPath();
    ctx.moveTo(x + 8, y + 10);
    ctx.lineTo(x + 40, y + 10);
    ctx.lineTo(x + 40, y + 40);
    ctx.bezierCurveTo(x + 40, y + 58, x + 30 + dir * 14, y + 64, x + 18 + dir * 10, y + 62);
    ctx.bezierCurveTo(x + 6, y + 60, x + 8, y + 48, x + 8, y + 40);
    ctx.closePath(); ctx.fill();
    // 袜口罗纹
    ctx.strokeStyle = '#66779a';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(x + 8, y + 16); ctx.lineTo(x + 40, y + 16); ctx.stroke();
    // 袜口 = 嘴巴：深色开口 + 两颗牙
    ctx.fillStyle = '#3c4a66';
    ctx.beginPath(); ctx.ellipse(cx, y + 10, 16, 6, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.moveTo(cx - 8, y + 8); ctx.lineTo(cx - 4, y + 8); ctx.lineTo(cx - 6, y + 14); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(cx + 4, y + 8); ctx.lineTo(cx + 8, y + 8); ctx.lineTo(cx + 6, y + 14); ctx.closePath(); ctx.fill();
    // 破洞：露出两只眼睛
    ctx.fillStyle = '#2c3244';
    ctx.beginPath(); ctx.ellipse(x + 18, y + 32, 7, 8, 0.2, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.ellipse(x + 33, y + 30, 6, 7, -0.2, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(x + 18, y + 31, 4, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 33, y + 29, 3.5, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(x + 18 + dir, y + 32, 2, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 33 + dir, y + 30, 1.8, 0, Math.PI * 2); ctx.fill();
    // 补丁 + 缝线
    ctx.fillStyle = '#9aa8c0';
    ctx.fillRect(x + 12, y + 46, 12, 9);
    ctx.strokeStyle = '#5a6a88';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(x + 12, y + 46, 12, 9);
    // 袜尖颜色深一点
    ctx.fillStyle = '#66779a';
    ctx.beginPath();
    ctx.ellipse(x + 18 + dir * 10, y + 60, 10, 5, dir * 0.3, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  },

  // ===== 臭气 =====
  stink: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var fade = 1 - e.t / e.dur;
    ctx.save();
    // 外圈扩散环
    ctx.globalAlpha = 0.7 * fade;
    ctx.strokeStyle = '#7ac74f';
    ctx.lineWidth = 6;
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.stroke();
    // 内部的臭气团
    ctx.globalAlpha = 0.35 * fade;
    ctx.fillStyle = '#8ed05f';
    for (var i = 0; i < 5; i++) {
      var a = i * 1.256 + e.t * 2;
      ctx.beginPath();
      ctx.arc(x + Math.cos(a) * e.r * 0.55, y + Math.sin(a) * e.r * 0.35, 12 + Math.sin(e.t * 6 + i) * 3, 0, Math.PI * 2);
      ctx.fill();
    }
    // 波浪臭气线
    ctx.globalAlpha = 0.8 * fade;
    ctx.strokeStyle = '#5a9a3a';
    ctx.lineWidth = 3;
    for (var w = 0; w < 3; w++) {
      var wx = x + Math.cos(w * 2.1 + e.t) * e.r * 0.4;
      var wy = y - 10 - w * 12;
      ctx.beginPath();
      ctx.moveTo(wx, wy);
      ctx.bezierCurveTo(wx - 6, wy - 8, wx + 6, wy - 14, wx, wy - 22);
      ctx.stroke();
    }
    ctx.restore();
  },

  // ===== 蛛丝球 =====
  webball: function (ctx, e, cam) {
    var x = e.x - cam.x + e.r, y = e.y + e.r;
    ctx.save();
    ctx.fillStyle = 'rgba(232,232,244,0.95)';
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.fill();
    // 蛛网丝纹
    ctx.strokeStyle = 'rgba(150,150,180,0.8)';
    ctx.lineWidth = 1.5;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(e.spin);
    for (var i = 0; i < 4; i++) {
      var a = (i / 4) * Math.PI;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a) * -e.r, Math.sin(a) * -e.r);
      ctx.lineTo(Math.cos(a) * e.r, Math.sin(a) * e.r);
      ctx.stroke();
    }
    ctx.beginPath(); ctx.arc(0, 0, e.r * 0.5, 0, Math.PI * 2); ctx.stroke();
    ctx.restore();
    ctx.fillStyle = 'rgba(255,255,255,0.8)';
    ctx.beginPath(); ctx.arc(x - 4, y - 4, 3, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  },

  // ===== 电锯（旋转飞来 —— 光头强扔出的小电锯）=====
  axe: function (ctx, e, cam) {
    var x = e.x - cam.x + e.w / 2, y = e.y + e.h / 2;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(e.spin);
    // 橙色锯身
    ctx.fillStyle = '#e8642a';
    Util.roundRect(ctx, -13, -8, 16, 16, 4);
    ctx.fillStyle = '#ffb37a';                 // 机身高光
    ctx.fillRect(-11, -6, 12, 3);
    // 黑色握把
    ctx.fillStyle = '#2a2a2a';
    Util.roundRect(ctx, -15, -13, 8, 8, 2);
    // 灰色导板
    ctx.fillStyle = '#b8bcc8';
    Util.roundRect(ctx, 2, -4, 15, 7, 2);
    ctx.beginPath();                            // 导板圆头
    ctx.arc(17, -0.5, 3.5, -Math.PI / 2, Math.PI / 2);
    ctx.fill();
    // 转动的锯齿
    ctx.fillStyle = '#8a8e9a';
    for (var i = 0; i < 4; i++) {
      ctx.beginPath();
      ctx.moveTo(4 + i * 3.5, 3); ctx.lineTo(6.5 + i * 3.5, 3); ctx.lineTo(5.2 + i * 3.5, 6);
      ctx.closePath(); ctx.fill();
    }
    ctx.restore();
  },

  // ===== 电锯气浪（贴地扩散的木屑气浪，跳起可躲）=====
  timeshock: function (ctx, e, cam) {
    var x = e.x - cam.x, gy = e.y + e.h;
    var a = Math.min(1, e.life);
    ctx.save();
    ctx.globalAlpha = 0.85 * a;
    ctx.strokeStyle = '#d99a3a';
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.ellipse(x + e.w / 2, gy, e.w * 0.8, e.h * 0.55, 0, Math.PI, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 0.4 * a;
    ctx.strokeStyle = '#f2d29a';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.ellipse(x + e.w / 2, gy, e.w * 1.15, e.h * 0.75, 0, Math.PI, Math.PI * 2);
    ctx.stroke();
    // 飞溅的木屑颗粒
    ctx.globalAlpha = 0.8 * a;
    ctx.fillStyle = '#e8c07a';
    for (var i = 0; i < 5; i++) {
      var aa = Math.PI + (i + 0.5) * Math.PI / 5;
      var tx = x + e.w / 2 + Math.cos(aa) * e.w * 0.95;
      var ty = gy + Math.sin(aa) * e.h * 0.7;
      ctx.fillRect(tx - 2, ty - 2, 4, 3);
    }
    ctx.restore();
  },

  // ===== 大蜘蛛兽（火星 Boss：八条腿的大蜘蛛）=====
  spiderboss: function (ctx, e, cam, t) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var dir = e.dir || 1;
    ctx.save();
    if (!e.alive) {
      // 死亡：腿缩起来 + 变淡
      var fall = Math.min(1, e.fallT / 1.2);
      ctx.translate(cx, y + e.h);
      ctx.rotate(dir * fall * 0.5);
      ctx.globalAlpha = Math.max(0.3, 1 - e.fallT * 0.3);
      ctx.translate(-cx, -(y + e.h));
    }
    var dead = !e.alive;
    // ----- 八条腿（左右各四条，两节，爬行时交替摆动）-----
    ctx.strokeStyle = '#3a2050';
    ctx.lineWidth = 7;
    ctx.lineCap = 'round';
    for (var side = -1; side <= 1; side += 2) {
      for (var li = 0; li < 4; li++) {
        var hipX = cx + side * (40 + li * 20);
        var hipY = y + 70 + li * 6;
        var sw = dead ? 0 : Math.sin(e.anim + li * 1.4 + (side > 0 ? Math.PI : 0)) * 10;
        var kneeX = hipX + side * (34 + (dead ? -6 : 0));
        var kneeY = hipY - 26 + sw * 0.4;
        var footX = hipX + side * (62 + (dead ? -16 : 0));
        var footY = y + e.h - 2 - Math.max(0, sw) * 0.5 - (dead ? 0 : Math.abs(Math.sin(e.anim * 0.5 + li)) * 4);
        ctx.beginPath();
        ctx.moveTo(hipX, hipY);
        ctx.lineTo(kneeX, kneeY);
        ctx.lineTo(footX, footY);
        ctx.stroke();
        // 腿节上的小尖
        ctx.fillStyle = '#5a3080';
        ctx.beginPath(); ctx.arc(kneeX, kneeY, 4.5, 0, Math.PI * 2); ctx.fill();
      }
    }
    // ----- 大肚子（腹部，深紫带洋红花纹）-----
    var bodyLift = (e.windupT > 0) ? -10 : 0;   // 扑击预警时抬起身子
    var g = ctx.createRadialGradient(cx - 20, y + 60 + bodyLift, 10, cx, y + 75 + bodyLift, 75);
    g.addColorStop(0, '#6a3a88');
    g.addColorStop(1, '#40205c');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.ellipse(cx, y + 78 + bodyLift, 72, 56, 0, 0, Math.PI * 2); ctx.fill();
    // 洋红花斑
    ctx.fillStyle = '#c04a8a';
    ctx.beginPath(); ctx.arc(cx - 24, y + 60 + bodyLift, 9, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 26, y + 68 + bodyLift, 7, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx, y + 96 + bodyLift, 8, 0, Math.PI * 2); ctx.fill();
    // ----- 头胸部（前面小一点）-----
    ctx.fillStyle = '#4a2870';
    ctx.beginPath(); ctx.ellipse(cx + dir * 58, y + 92 + bodyLift, 36, 28, 0, 0, Math.PI * 2); ctx.fill();
    // ----- 眼睛（前面一堆亮黄小眼睛：两大四小）-----
    var ex = cx + dir * 66, ey = y + 82 + bodyLift;
    ctx.fillStyle = '#ffe14a';
    ctx.beginPath(); ctx.arc(ex - 8, ey, 7, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex + 8, ey, 7, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex - 16, ey + 10, 4, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex + 16, ey + 10, 4, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex - 5, ey + 13, 3.5, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex + 5, ey + 13, 3.5, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(ex - 8 + dir * 2, ey + 1, 3, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex + 8 + dir * 2, ey + 1, 3, 0, Math.PI * 2); ctx.fill();
    // 毒牙（卡通小尖牙，不吓人）
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.moveTo(ex - 10, ey + 18); ctx.lineTo(ex - 5, ey + 18); ctx.lineTo(ex - 7.5, ey + 27);
    ctx.closePath(); ctx.fill();
    ctx.beginPath();
    ctx.moveTo(ex + 5, ey + 18); ctx.lineTo(ex + 10, ey + 18); ctx.lineTo(ex + 7.5, ey + 27);
    ctx.closePath(); ctx.fill();
    // 受击闪白
    if (e.hurtT > 0) {
      ctx.globalAlpha = Math.min(0.85, e.hurtT * 6);
      ctx.fillStyle = '#fff';
      ctx.beginPath(); ctx.ellipse(cx, y + 78 + bodyLift, 72, 56, 0, 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = 1;
    }
    ctx.restore();
    // 扑击预警「!」
    if (e.alive && e.windupT > 0) {
      this.strokeText(ctx, '!', cx, y - 40, 48, '#ffe14a', '#7a1a1a', 7);
    }
    // 血条（活着才显示）
    if (e.alive) {
      var bw = 150, bx = cx - bw / 2, by = y - 24;
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      Util.roundRect(ctx, bx - 3, by - 3, bw + 6, 14, 6);
      ctx.fillStyle = '#571a24';
      Util.roundRect(ctx, bx, by, bw, 8, 4);
      var frac = e.maxHp > 0 ? e.hp / e.maxHp : 0;
      if (frac > 0) {
        ctx.fillStyle = frac > 0.35 ? '#e83a4a' : '#ff9a2a';
        Util.roundRect(ctx, bx, by, Math.max(6, bw * frac), 8, 4);
      }
    }
  },

  // ===== 魔鬼兽（第 4 幕 Boss：红色飞行小恶魔，双角尖尾蝙蝠翅，悬浮+吐火+俯冲）=====
  devilbeast: function (ctx, e, cam, t) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var dir = e.dir || -1;
    ctx.save();
    if (!e.alive) {
      var fall = Math.min(1, e.fallT / 1.0);
      ctx.translate(cx, y + e.h);
      ctx.rotate(dir * fall * 1.4);
      ctx.globalAlpha = Math.max(0.25, 1 - e.fallT * 0.35);
      ctx.translate(-cx, -(y + e.h));
    }
    var flap = Math.sin(e.anim * 2) * 14;
    // 蝙蝠翅（左右）
    ctx.fillStyle = '#7a1020';
    ctx.beginPath(); ctx.moveTo(cx - 50, y + 50); ctx.lineTo(cx - 92, y + 30 - flap);
    ctx.lineTo(cx - 78, y + 64); ctx.lineTo(cx - 96, y + 78 + flap); ctx.lineTo(cx - 50, y + 78); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(cx + 50, y + 50); ctx.lineTo(cx + 92, y + 30 - flap);
    ctx.lineTo(cx + 78, y + 64); ctx.lineTo(cx + 96, y + 78 + flap); ctx.lineTo(cx + 50, y + 78); ctx.closePath(); ctx.fill();
    // 身体（红色圆肚）
    var g = ctx.createRadialGradient(cx - 16, y + 50, 8, cx, y + 70, 70);
    g.addColorStop(0, '#e83a3a'); g.addColorStop(1, '#a01420');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.ellipse(cx, y + 70, 50, 56, 0, 0, Math.PI * 2); ctx.fill();
    // 尖尾
    ctx.fillStyle = '#c01a2a';
    ctx.beginPath(); ctx.moveTo(cx - dir * 30, y + 110); ctx.lineTo(cx - dir * 64, y + 96); ctx.lineTo(cx - dir * 58, y + 118); ctx.closePath(); ctx.fill();
    // 双角
    ctx.fillStyle = '#ffe7c0';
    ctx.beginPath(); ctx.moveTo(cx - 26, y + 24); ctx.lineTo(cx - 34, y - 14); ctx.lineTo(cx - 14, y + 26); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(cx + 26, y + 24); ctx.lineTo(cx + 34, y - 14); ctx.lineTo(cx + 14, y + 26); ctx.closePath(); ctx.fill();
    // 大嘴獠牙
    ctx.fillStyle = '#3a0008';
    ctx.beginPath(); ctx.ellipse(cx, y + 88, 22, 14, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.moveTo(cx - 12, y + 92); ctx.lineTo(cx - 6, y + 92); ctx.lineTo(cx - 9, y + 104); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(cx + 6, y + 92); ctx.lineTo(cx + 12, y + 92); ctx.lineTo(cx + 9, y + 104); ctx.closePath(); ctx.fill();
    // 眼睛（黄）
    ctx.fillStyle = '#ffe14a';
    ctx.beginPath(); ctx.arc(cx - 16, y + 56, 8, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 16, y + 56, 8, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(cx - 16 + dir * 2, y + 57, 3.5, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 16 + dir * 2, y + 57, 3.5, 0, Math.PI * 2); ctx.fill();
    if (e.hurtT > 0) {
      ctx.globalAlpha = Math.min(0.85, e.hurtT * 6);
      ctx.fillStyle = '#fff';
      ctx.beginPath(); ctx.ellipse(cx, y + 70, 50, 56, 0, 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = 1;
    }
    ctx.restore();
    if (e.alive && e.windupT > 0) { this.strokeText(ctx, '!', cx, y - 24, 44, '#ffe14a', '#7a1a1a', 7); }
    if (e.alive) {
      var bw = 130, bx = cx - bw / 2, by = y - 18;
      ctx.fillStyle = 'rgba(0,0,0,0.55)'; Util.roundRect(ctx, bx - 3, by - 3, bw + 6, 14, 6);
      ctx.fillStyle = '#571a24'; Util.roundRect(ctx, bx, by, bw, 8, 4);
      var frac = e.maxHp > 0 ? e.hp / e.maxHp : 0;
      if (frac > 0) { ctx.fillStyle = frac > 0.35 ? '#e83a4a' : '#ff9a2a'; Util.roundRect(ctx, bx, by, Math.max(6, bw * frac), 8, 4); }
    }
  },

  // ===== 大螃蟹兽（第 6 幕 Boss：红色大螃蟹，八条短腿，两只大钳，一只巨大）=====
  crabbeast: function (ctx, e, cam, t) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var dir = e.dir || -1;
    ctx.save();
    if (!e.alive) {
      var fall = Math.min(1, e.fallT / 1.0);
      ctx.translate(cx, y + e.h);
      ctx.rotate(dir * fall * 1.2);
      ctx.globalAlpha = Math.max(0.25, 1 - e.fallT * 0.35);
      ctx.translate(-cx, -(y + e.h));
    }
    var wind = e.windupT > 0;
    // 八条短腿（左右各四）
    ctx.strokeStyle = '#9a2420'; ctx.lineWidth = 6; ctx.lineCap = 'round';
    for (var sgn = -1; sgn <= 1; sgn += 2) {
      for (var li = 0; li < 4; li++) {
        var hx = cx + sgn * (50 + li * 22);
        var sw = wind ? 0 : Math.sin(e.anim + li) * 6;
        ctx.beginPath(); ctx.moveTo(hx, y + 60); ctx.lineTo(hx + sgn * 18, y + 96 + sw); ctx.stroke();
      }
    }
    // 身体（红色椭圆 + 壳纹）
    var g = ctx.createRadialGradient(cx - 20, y + 30, 10, cx, y + 55, 90);
    g.addColorStop(0, '#e94a3a'); g.addColorStop(1, '#a8241c');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.ellipse(cx, y + 56, 88, 52, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#8a1c16';
    ctx.beginPath(); ctx.arc(cx - 26, y + 44, 10, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 26, y + 48, 8, 0, Math.PI * 2); ctx.fill();
    // 眼柄 + 眼睛
    ctx.strokeStyle = '#8a1c16'; ctx.lineWidth = 5;
    ctx.beginPath(); ctx.moveTo(cx - 18, y + 20); ctx.lineTo(cx - 18, y + 4); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx + 18, y + 20); ctx.lineTo(cx + 18, y + 4); ctx.stroke();
    ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(cx - 18, y + 2, 7, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 18, y + 2, 7, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a'; ctx.beginPath(); ctx.arc(cx - 18, y + 2, 3, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 18, y + 2, 3, 0, Math.PI * 2); ctx.fill();
    // 普通钳（小，朝后）
    ctx.fillStyle = '#c8302a';
    var smallCx = cx - dir * 96;
    ctx.beginPath(); ctx.ellipse(smallCx, y + 50, 16, 12, 0, 0, Math.PI * 2); ctx.fill();
    // 巨钳（大，朝前/面向玩家）
    var bigCx = cx + dir * 96;
    var clY = wind ? y + 28 : y + 54;
    ctx.fillStyle = '#d8382c';
    ctx.beginPath(); ctx.ellipse(bigCx, clY, 30, 22, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#a8241c';
    ctx.beginPath(); ctx.moveTo(bigCx + dir * 18, clY - 18); ctx.lineTo(bigCx + dir * 46, clY - 6); ctx.lineTo(bigCx + dir * 18, clY + 6); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(bigCx + dir * 18, clY + 4); ctx.lineTo(bigCx + dir * 46, clY + 16); ctx.lineTo(bigCx + dir * 18, clY + 22); ctx.closePath(); ctx.fill();
    if (e.hurtT > 0) {
      ctx.globalAlpha = Math.min(0.85, e.hurtT * 6);
      ctx.fillStyle = '#fff';
      ctx.beginPath(); ctx.ellipse(cx, y + 56, 88, 52, 0, 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = 1;
    }
    ctx.restore();
    if (e.alive && e.windupT > 0) { this.strokeText(ctx, '!', cx, y - 22, 44, '#ffe14a', '#7a1a1a', 7); }
    if (e.alive) {
      var bw = 150, bx = cx - bw / 2, by = y - 24;
      ctx.fillStyle = 'rgba(0,0,0,0.55)'; Util.roundRect(ctx, bx - 3, by - 3, bw + 6, 14, 6);
      ctx.fillStyle = '#571a24'; Util.roundRect(ctx, bx, by, bw, 8, 4);
      var frac = e.maxHp > 0 ? e.hp / e.maxHp : 0;
      if (frac > 0) { ctx.fillStyle = frac > 0.35 ? '#e83a4a' : '#ff9a2a'; Util.roundRect(ctx, bx, by, Math.max(6, bw * frac), 8, 4); }
    }
  },

  // ===== 中级蜘蛛兽（骷髅头蜘蛛兽，第 7 幕 Boss：比大蜘蛛兽更大，头是骷髅）=====
  midspider: function (ctx, e, cam, t) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var dir = e.dir || 1;
    ctx.save();
    if (!e.alive) {
      var fall = Math.min(1, e.fallT / 1.2);
      ctx.translate(cx, y + e.h);
      ctx.rotate(dir * fall * 0.5);
      ctx.globalAlpha = Math.max(0.3, 1 - e.fallT * 0.3);
      ctx.translate(-cx, -(y + e.h));
    }
    var dead = !e.alive;
    // 八条腿（比大蜘蛛兽粗一点）
    ctx.strokeStyle = '#5a5a4a'; ctx.lineWidth = 9; ctx.lineCap = 'round';
    for (var side = -1; side <= 1; side += 2) {
      for (var li = 0; li < 4; li++) {
        var hipX = cx + side * (46 + li * 22);
        var hipY = y + 80 + li * 7;
        var sw = dead ? 0 : Math.sin(e.anim + li * 1.4 + (side > 0 ? Math.PI : 0)) * 11;
        var kneeX = hipX + side * (38 + (dead ? -6 : 0));
        var kneeY = hipY - 28 + sw * 0.4;
        var footX = hipX + side * (70 + (dead ? -16 : 0));
        var footY = y + e.h - 2 - Math.max(0, sw) * 0.5 - (dead ? 0 : Math.abs(Math.sin(e.anim * 0.5 + li)) * 4);
        ctx.beginPath(); ctx.moveTo(hipX, hipY); ctx.lineTo(kneeX, kneeY); ctx.lineTo(footX, footY); ctx.stroke();
      }
    }
    // 腹部（深灰带暗纹）
    var bodyLift = (e.windupT > 0) ? -12 : 0;
    var g = ctx.createRadialGradient(cx - 22, y + 64 + bodyLift, 12, cx, y + 82 + bodyLift, 84);
    g.addColorStop(0, '#6a6a5e'); g.addColorStop(1, '#3a3a30');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.ellipse(cx, y + 84 + bodyLift, 78, 60, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#4a4a3c';
    ctx.beginPath(); ctx.arc(cx - 26, y + 66 + bodyLift, 9, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 28, y + 74 + bodyLift, 7, 0, Math.PI * 2); ctx.fill();
    // 骷髅头（替代普通头胸）
    var sx = cx + dir * 62, sy = y + 96 + bodyLift;
    ctx.fillStyle = '#ece6d8';
    ctx.beginPath(); ctx.ellipse(sx, sy, 34, 38, 0, 0, Math.PI * 2); ctx.fill();   // 颅骨
    ctx.fillStyle = '#d8d2c4';
    ctx.beginPath(); ctx.ellipse(sx, sy + 30, 22, 14, 0, 0, Math.PI * 2); ctx.fill(); // 下颌
    ctx.fillStyle = '#161410';
    ctx.beginPath(); ctx.arc(sx - 13, sy - 4, 11, 0, Math.PI * 2); ctx.fill();       // 眼窝
    ctx.beginPath(); ctx.arc(sx + 13, sy - 4, 11, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#7dff5a';
    ctx.beginPath(); ctx.arc(sx - 13, sy - 4, 4, 0, Math.PI * 2); ctx.fill();       // 绿光眼
    ctx.beginPath(); ctx.arc(sx + 13, sy - 4, 4, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(sx - 4, sy + 12, 3, 0, Math.PI * 2); ctx.fill();       // 鼻孔
    ctx.beginPath(); ctx.arc(sx + 4, sy + 12, 3, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff';
    for (var ti = -3; ti <= 3; ti++) { ctx.fillRect(sx + ti * 6 - 2, sy + 24, 4, 9); }  // 牙齿
    if (e.hurtT > 0) {
      ctx.globalAlpha = Math.min(0.85, e.hurtT * 6);
      ctx.fillStyle = '#fff';
      ctx.beginPath(); ctx.ellipse(cx, y + 84 + bodyLift, 78, 60, 0, 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = 1;
    }
    ctx.restore();
    if (e.alive && e.windupT > 0) { this.strokeText(ctx, '!', cx, y - 44, 48, '#7dff5a', '#1a3a10', 7); }
    if (e.alive) {
      var bw = 150, bx = cx - bw / 2, by = y - 26;
      ctx.fillStyle = 'rgba(0,0,0,0.55)'; Util.roundRect(ctx, bx - 3, by - 3, bw + 6, 14, 6);
      ctx.fillStyle = '#571a24'; Util.roundRect(ctx, bx, by, bw, 8, 4);
      var frac = e.maxHp > 0 ? e.hp / e.maxHp : 0;
      if (frac > 0) { ctx.fillStyle = frac > 0.35 ? '#e83a4a' : '#ff9a2a'; Util.roundRect(ctx, bx, by, Math.max(6, bw * frac), 8, 4); }
    }
  },

  // ===== 幼蛛（小蜘蛛；贴地爬、可踩扁）=====
  spiderling: function (ctx, e, cam, t) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var dir = e.dir || 1;
    ctx.save();
    if (!e.alive) {
      var fall = Math.min(1, e.deadT / 0.6);
      ctx.translate(cx, y + e.h);
      ctx.rotate(dir * fall * 0.5);
      ctx.globalAlpha = Math.max(0.3, 1 - e.deadT);
      ctx.translate(-cx, -(y + e.h));
    }
    var dead = !e.alive;
    // 六条腿
    ctx.strokeStyle = '#5a5a4a'; ctx.lineWidth = 5; ctx.lineCap = 'round';
    for (var side = -1; side <= 1; side += 2) {
      for (var li = 0; li < 3; li++) {
        var hipX = cx + side * (24 + li * 12);
        var hipY = y + 46 + li * 5;
        var sw = dead ? 0 : Math.sin(e.anim + li * 1.4 + (side > 0 ? Math.PI : 0)) * 6;
        var kneeX = hipX + side * 18;
        var kneeY = hipY - 18 + sw * 0.4;
        var footX = hipX + side * 30;
        var footY = y + e.h - 4 - Math.max(0, sw) * 0.5;
        ctx.beginPath(); ctx.moveTo(hipX, hipY); ctx.lineTo(kneeX, kneeY); ctx.lineTo(footX, footY); ctx.stroke();
      }
    }
    var g = ctx.createRadialGradient(cx - 18, y + 52, 8, cx, y + 64, 42);
    g.addColorStop(0, '#6a6a5e'); g.addColorStop(1, '#3a3a30');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.ellipse(cx, y + 64, 40, 30, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#7dff5a';
    ctx.beginPath(); ctx.arc(cx - 10, y + 60, 4, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 10, y + 60, 4, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  },

  // ===== 光头强（最终 Boss：橙黄毛线帽 + 绿色背带工装 + 大鼻子 + 络腮胡茬的伐木工反派，原创画法）=====
  timedevourer: function (ctx, e, cam, t) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var dir = e.dir || 1;
    ctx.save();
    // 一溜烟窜位：淡出 / 淡入
    var alpha = 1;
    if (e.blinkOut > 0) alpha = Math.max(0, e.blinkOut / 0.4);
    else if (e.blinkIn > 0) alpha = 1 - Math.max(0, e.blinkIn / 0.4);
    if (!e.alive) {
      // 倒下：绕脚旋转倒地 + 变淡
      var fall = Math.min(1, e.fallT / 1.0);
      ctx.translate(cx, y + e.h);
      ctx.rotate(dir * fall * 1.4);
      ctx.globalAlpha = Math.max(0.25, 1 - e.fallT * 0.35);
      ctx.translate(-cx, -(y + e.h));
    } else if (alpha < 1) {
      ctx.globalAlpha = alpha;
    }
    var walking = e.alive && e.blinkOut <= 0;
    var step = walking ? Math.sin(e.anim) * 5 : 0;
    // ----- 棕色大工靴 -----
    ctx.fillStyle = '#5a3a1e';
    ctx.fillRect(cx - 23 + step, y + e.h - 13, 22, 13);
    ctx.fillRect(cx + 1 - step, y + e.h - 13, 22, 13);
    ctx.fillStyle = '#3a2410';
    ctx.fillRect(cx - 23 + step, y + e.h - 4, 22, 4);
    ctx.fillRect(cx + 1 - step, y + e.h - 4, 22, 4);
    // ----- 绿色工装裤（光头强招牌绿）-----
    ctx.fillStyle = '#3f7a34';
    ctx.fillRect(cx - 20 + step * 0.6, y + 108, 18, e.h - 120);
    ctx.fillRect(cx + 2 - step * 0.6, y + 108, 18, e.h - 120);
    // ----- 手臂（浅色卷袖 + 手）-----
    ctx.fillStyle = '#e8d8b0';
    ctx.fillRect(cx - 40, y + 66 + step * 0.4, 13, 34);
    ctx.fillRect(cx + 27, y + 66 - step * 0.4, 13, 34);
    ctx.fillStyle = '#f0c090';
    ctx.beginPath(); ctx.arc(cx - 34, y + 104 + step * 0.4, 7.5, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 34, y + 104 - step * 0.4, 7.5, 0, Math.PI * 2); ctx.fill();
    // ----- 绿色背带工装（里面浅色 T 恤 + 绿色背带工装）-----
    ctx.fillStyle = '#e9dcc0';                     // 里面的浅色 T 恤
    Util.roundRect(ctx, cx - 30, y + 60, 60, 54, 10);
    ctx.fillStyle = '#3f7a34';                     // 绿色背带工装身
    Util.roundRect(ctx, cx - 26, y + 76, 52, 40, 6);
    // 背带（两条肩带）
    ctx.fillStyle = '#357029';
    ctx.fillRect(cx - 20, y + 60, 9, 24);
    ctx.fillRect(cx + 11, y + 60, 9, 24);
    // 工装口袋 + 铜扣
    ctx.strokeStyle = '#2c5a22';
    ctx.lineWidth = 2;
    ctx.strokeRect(cx - 12, y + 90, 24, 18);
    ctx.fillStyle = '#f2c84a';
    ctx.beginPath(); ctx.arc(cx - 15, y + 82, 3, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 15, y + 82, 3, 0, Math.PI * 2); ctx.fill();
    // ----- 手里的电锯（光头强招牌武器，扔不完的电锯）-----
    ctx.save();
    ctx.translate(cx + 40, y + 98 - step * 0.4);
    ctx.rotate(-0.15 + (walking ? Math.sin(e.anim * 0.5) * 0.12 : 0));
    if (dir < 0) ctx.scale(-1, 1);
    // 锯身（橙色机身）
    ctx.fillStyle = '#e8642a';
    Util.roundRect(ctx, -12, -12, 22, 20, 5);
    ctx.fillStyle = '#2a2a2a';                     // 握把
    Util.roundRect(ctx, -14, -18, 10, 10, 3);
    // 导板 + 锯齿
    ctx.fillStyle = '#b8bcc8';
    Util.roundRect(ctx, 8, -6, 30, 8, 3);
    ctx.fillStyle = '#7a7e8a';
    for (var gi = 0; gi < 6; gi++) {
      ctx.beginPath();
      ctx.moveTo(12 + gi * 5, 2); ctx.lineTo(15 + gi * 5, 2); ctx.lineTo(13.5 + gi * 5, 6);
      ctx.closePath(); ctx.fill();
    }
    ctx.restore();
    // ----- 头（皮肤色，光头顶 + 高光）-----
    ctx.fillStyle = '#f2c99a';
    ctx.beginPath(); ctx.arc(cx, y + 34, 27, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.45)';
    ctx.beginPath(); ctx.ellipse(cx - 9, y + 22, 7, 4, -0.5, 0, Math.PI * 2); ctx.fill();
    // ----- 两侧黑色短发（从毛线帽下露出来）-----
    ctx.fillStyle = '#211a12';
    ctx.beginPath(); ctx.ellipse(cx - 25, y + 30, 6, 10, 0.25, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.ellipse(cx + 25, y + 30, 6, 10, -0.25, 0, Math.PI * 2); ctx.fill();
    // ----- 络腮胡茬（青色胡渣，围下巴一圈）-----
    ctx.fillStyle = 'rgba(90,70,50,0.85)';
    ctx.beginPath();
    ctx.arc(cx, y + 43, 23, 0.08 * Math.PI, 0.92 * Math.PI);
    ctx.arc(cx, y + 38, 15, 0.92 * Math.PI, 0.08 * Math.PI, true);
    ctx.closePath(); ctx.fill();
    // ----- 大鼻子（光头强招牌大鼻子）-----
    ctx.fillStyle = '#e8a878';
    ctx.beginPath(); ctx.ellipse(cx + dir * 2, y + 40, 8, 6.5, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.4)';
    ctx.beginPath(); ctx.arc(cx + dir * 2 - 2, y + 38, 2, 0, Math.PI * 2); ctx.fill();
    // 嘴（坏笑）
    ctx.strokeStyle = '#7a3a2a';
    ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.arc(cx, y + 48, 7, 0.12 * Math.PI, 0.88 * Math.PI); ctx.stroke();
    // ----- 凶凶的粗眉毛 + 眼睛 -----
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(cx - 10, y + 29, 6, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 10, y + 29, 6, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(cx - 10 + dir * 2, y + 30, 3, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + 10 + dir * 2, y + 30, 3, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = '#211a12';
    ctx.lineWidth = 4;
    ctx.beginPath(); ctx.moveTo(cx - 18, y + 19); ctx.lineTo(cx - 4, y + 24); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx + 18, y + 19); ctx.lineTo(cx + 4, y + 24); ctx.stroke();
    // ----- 橙黄色毛线帽（光头强招牌）-----
    ctx.fillStyle = '#f2a01e';
    ctx.beginPath(); ctx.arc(cx, y + 18, 25, Math.PI, 0); ctx.closePath(); ctx.fill();
    ctx.fillRect(cx - 25, y + 14, 50, 8);
    // 毛线帽罗纹（竖纹）
    ctx.strokeStyle = '#d9860e';
    ctx.lineWidth = 2;
    for (var ri = -3; ri <= 3; ri++) {
      ctx.beginPath(); ctx.moveTo(cx + ri * 7, y - 4); ctx.lineTo(cx + ri * 7, y + 20); ctx.stroke();
    }
    // 帽顶小绒球
    ctx.fillStyle = '#ffd06a';
    ctx.beginPath(); ctx.arc(cx, y - 6, 6, 0, Math.PI * 2); ctx.fill();
    // 帽檐折边
    ctx.fillStyle = '#d9860e';
    ctx.fillRect(cx - 26, y + 20, 52, 5);
    // 受击闪白
    if (e.hurtT > 0) {
      ctx.globalAlpha = Math.min(0.8, e.hurtT * 6);
      ctx.fillStyle = '#fff';
      Util.roundRect(ctx, cx - 34, y - 10, 68, e.h, 20);
      ctx.globalAlpha = 1;
    }
    // 生气（第二阶段）/ 变身特效
    if (e.phase === 2 || e.transitionT > 0) {
      // 冒蒸汽（愤怒的热气）
      ctx.fillStyle = 'rgba(255,255,255,0.5)';
      for (var si = 0; si < 3; si++) {
        var sxp2 = cx - 18 + si * 18 + Math.sin(e.anim * 3 + si) * 4;
        var rise = (e.anim * 40 + si * 30) % 50;
        var syp2 = y - 14 - rise;
        ctx.beginPath(); ctx.arc(sxp2, syp2, 4 - rise / 50 * 2, 0, Math.PI * 2); ctx.fill();
      }
      if (e.transitionT > 0) {
        ctx.globalAlpha = Math.min(0.7, e.transitionT);
        ctx.fillStyle = '#ff3a2a';
        Util.roundRect(ctx, cx - 34, y - 10, 68, e.h, 20);
        ctx.globalAlpha = 1;
        this.strokeText(ctx, '!!!', cx, y + 6, 30, '#fff', '#000', 5);
      } else {
        // 第二阶段：脸涨红 + 更凶的红眉毛
        ctx.fillStyle = 'rgba(220,60,40,0.28)';
        ctx.beginPath(); ctx.arc(cx, y + 34, 27, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = '#c01010'; ctx.lineWidth = 5;
        ctx.beginPath(); ctx.moveTo(cx - 18, y + 22); ctx.lineTo(cx - 4, y + 26); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(cx + 18, y + 22); ctx.lineTo(cx + 4, y + 26); ctx.stroke();
      }
    }
    ctx.restore();
    // 血条（活着才显示）
    if (e.alive) {
      var bw = 150, bx = cx - bw / 2, by = y - 30;
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      Util.roundRect(ctx, bx - 3, by - 3, bw + 6, 14, 6);
      ctx.fillStyle = '#571a24';
      Util.roundRect(ctx, bx, by, bw, 8, 4);
      var frac = e.maxHp > 0 ? e.hp / e.maxHp : 0;
      if (frac > 0) {
        ctx.fillStyle = e.phase === 2 ? '#ff5a2a' : (frac > 0.35 ? '#e83a4a' : '#ff9a2a');
        Util.roundRect(ctx, bx, by, Math.max(6, bw * frac), 8, 4);
      }
      // 第二阶段分割线 + 阶段标记
      var showSplit = e.phase === 2 || e.hp <= e.maxHp * BOSS_PHASE2_FRAC;
      if (showSplit) {
        ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.moveTo(bx + bw * BOSS_PHASE2_FRAC, by - 2); ctx.lineTo(bx + bw * BOSS_PHASE2_FRAC, by + 10); ctx.stroke();
        this.text(ctx, '1', bx + bw * 0.25, by - 12, 14, '#fff', 'center', true);
        this.text(ctx, '2', bx + bw * 0.75, by - 12, 14, '#ffb060', 'center', true);
      }
    }
  },

  // ===== H 子弹 =====
  bullet: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var dir = Util.sign(e.vx) || 1;
    ctx.save();
    // 速度线
    ctx.strokeStyle = 'rgba(255,240,160,0.7)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x + e.w / 2 - dir * 12, y + e.h / 2);
    ctx.lineTo(x + e.w / 2 - dir * 26, y + e.h / 2);
    ctx.stroke();
    // 金黄小弹丸
    ctx.fillStyle = '#ffd94a';
    Util.roundRect(ctx, x, y, e.w, e.h, 4);
    ctx.fillStyle = '#fff2b0';
    ctx.fillRect(x + 2, y + 1.5, e.w - 8, 2.5);
    ctx.restore();
  },

  // ===== J 火球 =====
  fireball: function (ctx, e, cam) {
    var x = e.x - cam.x + e.r, y = e.y + e.r;
    var dir = Util.sign(e.vx) || 1;
    ctx.save();
    // 外焰
    ctx.globalAlpha = 0.45;
    ctx.fillStyle = '#ff5a1a';
    ctx.beginPath(); ctx.arc(x, y, e.r + 4 + Math.sin(e.spin * 3) * 2, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
    // 球体（中心亮黄，边缘橙红）
    var g = ctx.createRadialGradient(x - 3, y - 3, 2, x, y, e.r);
    g.addColorStop(0, '#fff2a0');
    g.addColorStop(0.55, '#ff9a2a');
    g.addColorStop(1, '#e84a10');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.fill();
    // 尾部小火苗
    ctx.fillStyle = 'rgba(255,122,42,0.7)';
    for (var i = 0; i < 3; i++) {
      ctx.beginPath();
      ctx.arc(x - dir * (e.r + 4 + i * 7), y + Math.sin(e.spin * 4 + i) * 3, 5 - i, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  },

  // 魔鬼兽的火焰弹（敌方投射物）：与玩家火球同款火焰，但偏暗红、不弹跳
  devilfire: function (ctx, e, cam) {
    var x = e.x - cam.x + e.r, y = e.y + e.r;
    var dir = Util.sign(e.vx) || 1;
    ctx.save();
    ctx.globalAlpha = 0.45;
    ctx.fillStyle = '#c01808';
    ctx.beginPath(); ctx.arc(x, y, e.r + 4 + Math.sin(e.spin * 3) * 2, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
    var g = ctx.createRadialGradient(x - 3, y - 3, 2, x, y, e.r);
    g.addColorStop(0, '#ffd070');
    g.addColorStop(0.55, '#ff6a1a');
    g.addColorStop(1, '#b01808');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(255,80,30,0.7)';
    for (var i = 0; i < 3; i++) {
      ctx.beginPath();
      ctx.arc(x - dir * (e.r + 4 + i * 7), y + Math.sin(e.spin * 4 + i) * 3, 5 - i, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  },

  // ===== K 大导弹 =====
  missile: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var dir = Util.sign(e.vx) || 1;
    ctx.save();
    ctx.translate(x + e.w / 2, y + e.h / 2);
    if (dir < 0) ctx.scale(-1, 1);
    // 尾焰
    var fl = 10 + Math.sin(e.life * 40) * 4;
    ctx.fillStyle = 'rgba(255,160,40,0.9)';
    ctx.beginPath();
    ctx.moveTo(-e.w / 2, -4);
    ctx.lineTo(-e.w / 2 - fl, 0);
    ctx.lineTo(-e.w / 2, 4);
    ctx.closePath(); ctx.fill();
    // 银色弹体
    var g = ctx.createLinearGradient(0, -8, 0, 8);
    g.addColorStop(0, '#f0f2f8');
    g.addColorStop(1, '#9aa0b8');
    ctx.fillStyle = g;
    Util.roundRect(ctx, -e.w / 2, -e.h / 2, e.w - 10, e.h, 7);
    // 红色弹头
    ctx.fillStyle = '#d93a3a';
    ctx.beginPath();
    ctx.moveTo(e.w / 2 - 12, -e.h / 2);
    ctx.lineTo(e.w / 2 + 2, 0);
    ctx.lineTo(e.w / 2 - 12, e.h / 2);
    ctx.closePath(); ctx.fill();
    // 尾翼
    ctx.fillStyle = '#d93a3a';
    ctx.beginPath();
    ctx.moveTo(-e.w / 2, -e.h / 2); ctx.lineTo(-e.w / 2 - 6, -e.h / 2 - 6); ctx.lineTo(-e.w / 2 + 6, -e.h / 2);
    ctx.closePath(); ctx.fill();
    ctx.beginPath();
    ctx.moveTo(-e.w / 2, e.h / 2); ctx.lineTo(-e.w / 2 - 6, e.h / 2 + 6); ctx.lineTo(-e.w / 2 + 6, e.h / 2);
    ctx.closePath(); ctx.fill();
    // 舷窗
    ctx.fillStyle = '#2a6fd6';
    ctx.beginPath(); ctx.arc(4, 0, 3.5, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  },

  // ===== L 原子弹 =====
  atombomb: function (ctx, e, cam) {
    var x = e.x - cam.x + e.r, y = e.y + e.r;
    ctx.save();
    // 墨绿大圆弹
    var g = ctx.createRadialGradient(x - 5, y - 5, 2, x, y, e.r);
    g.addColorStop(0, '#5a7a4a');
    g.addColorStop(1, '#2a3a26');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.fill();
    // 黄色辐射标志（三瓣）
    ctx.fillStyle = '#ffd94a';
    for (var i = 0; i < 3; i++) {
      var a = e.spin + i * (Math.PI * 2 / 3);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.arc(x, y, e.r * 0.6, a - 0.35, a + 0.35);
      ctx.closePath(); ctx.fill();
    }
    ctx.fillStyle = '#2a3a26';
    ctx.beginPath(); ctx.arc(x, y, e.r * 0.22, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#ffd94a';
    ctx.beginPath(); ctx.arc(x, y, e.r * 0.12, 0, Math.PI * 2); ctx.fill();
    // 顶端引线火花
    ctx.fillStyle = Math.sin(e.spin * 6) > 0 ? '#ffe14a' : '#ff8a2a';
    ctx.beginPath(); ctx.arc(x, y - e.r - 3, 3, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  },

  // ===== U 氢弹 =====
  hydrogenbomb: function (ctx, e, cam) {
    var x = e.x - cam.x + e.r, y = e.y + e.r;
    ctx.save();
    // 蓝色能量光晕
    ctx.globalAlpha = 0.35 + 0.15 * Math.sin(e.spin * 4);
    ctx.fillStyle = '#5ab0ff';
    ctx.beginPath(); ctx.arc(x, y, e.r + 7, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
    // 白银大圆弹
    var g = ctx.createRadialGradient(x - 6, y - 6, 2, x, y, e.r);
    g.addColorStop(0, '#ffffff');
    g.addColorStop(1, '#8a9ab8');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.fill();
    // 蓝色「H」标志
    ctx.fillStyle = '#2a6fd6';
    ctx.fillRect(x - 7, y - 7, 4, 14);
    ctx.fillRect(x + 3, y - 7, 4, 14);
    ctx.fillRect(x - 7, y - 2, 14, 4);
    // 尾翼
    ctx.fillStyle = '#5a7ae0';
    ctx.beginPath();
    ctx.moveTo(x - e.r + 3, y - 4); ctx.lineTo(x - e.r - 7, y); ctx.lineTo(x - e.r + 3, y + 4);
    ctx.closePath(); ctx.fill();
    ctx.restore();
  },

  // ===== 爆炸（冲击光环由小变大）=====
  explosion: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var prog = Util.clamp(e.t / e.dur, 0, 1);
    var fade = 1 - prog;
    ctx.save();
    // 中心白闪（刚炸的一瞬间）
    if (prog < 0.3) {
      ctx.globalAlpha = (0.3 - prog) / 0.3 * 0.9;
      ctx.fillStyle = '#fff8d0';
      ctx.beginPath(); ctx.arc(x, y, e.r * 0.8, 0, Math.PI * 2); ctx.fill();
    }
    // 外圈橙红冲击环
    ctx.globalAlpha = 0.85 * fade;
    ctx.strokeStyle = '#ff6a2a';
    ctx.lineWidth = Math.max(3, 16 * fade);
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, Math.PI * 2); ctx.stroke();
    // 内圈金黄环
    ctx.globalAlpha = 0.7 * fade;
    ctx.strokeStyle = '#ffd94a';
    ctx.lineWidth = Math.max(2, 9 * fade);
    ctx.beginPath(); ctx.arc(x, y, e.r * 0.72, 0, Math.PI * 2); ctx.stroke();
    // 飞溅的小火点
    ctx.globalAlpha = 0.8 * fade;
    ctx.fillStyle = '#ffb040';
    for (var i = 0; i < 8; i++) {
      var a = i * 0.785 + 0.4;
      ctx.beginPath();
      ctx.arc(x + Math.cos(a) * e.r * 0.92, y + Math.sin(a) * e.r * 0.92, 4 + 4 * fade, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  },

  // ===== 火箭（宇航员乘坐的发射火箭：底部两个支撑腿、顶部 6 个尖角、车身上没有窗户）=====
  rocket: function (ctx, r, cam, t) {
    var x = r.x - cam.x, y = r.y;
    var flame = r.flameT || 0;
    ctx.save();
    // 喷火（在底部）
    if (flame > 0) {
      var fl = 45 + Math.sin(t * 40) * 18 + flame * 30;
      ctx.fillStyle = 'rgba(255,180,40,0.9)';
      ctx.beginPath();
      ctx.moveTo(x + 21, y + 182); ctx.lineTo(x + 60, y + 182); ctx.lineTo(x + 40.5, y + 182 + fl); ctx.closePath(); ctx.fill();
      ctx.fillStyle = 'rgba(255,240,120,0.9)';
      ctx.beginPath();
      ctx.moveTo(x + 27, y + 182); ctx.lineTo(x + 54, y + 182); ctx.lineTo(x + 40.5, y + 182 + fl * 0.6); ctx.closePath(); ctx.fill();
    }
    // 两个支撑腿（底部外八字）
    ctx.strokeStyle = '#9a9aa6'; ctx.lineWidth = 7; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(x + 16, y + 176); ctx.lineTo(x - 4, y + 214); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x + 65, y + 176); ctx.lineTo(x + 85, y + 214); ctx.stroke();
    // 脚垫
    ctx.fillStyle = '#7c7c88';
    ctx.fillRect(x - 16, y + 212, 22, 9);
    ctx.fillRect(x + 73, y + 212, 22, 9);
    // 主鳍（左右）
    ctx.fillStyle = '#d33';
    ctx.beginPath(); ctx.moveTo(x + 9, y + 166); ctx.lineTo(x + 9, y + 144); ctx.lineTo(x - 12, y + 182); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(x + 72, y + 166); ctx.lineTo(x + 72, y + 144); ctx.lineTo(x + 93, y + 182); ctx.closePath(); ctx.fill();
    // 主体（车身上没有窗户）
    ctx.fillStyle = '#f4f4f8';
    Util.roundRect(ctx, x + 9, y + 54, 63, 124, 12);
    ctx.fillStyle = '#d33';
    ctx.fillRect(x + 9, y + 118, 63, 10);
    // 头锥
    ctx.fillStyle = '#d33';
    ctx.beginPath(); ctx.moveTo(x + 9, y + 60); ctx.lineTo(x + 40.5, y + 10); ctx.lineTo(x + 72, y + 60); ctx.closePath(); ctx.fill();
    // 顶部 6 个尖角（排成一行的小三角）
    ctx.fillStyle = '#eef0f6';
    var spikeW = 13.5, baseY = y + 12;
    for (var si = 0; si < 6; si++) {
      var sx2 = x + 4 + si * spikeW;
      ctx.beginPath();
      ctx.moveTo(sx2, baseY);
      ctx.lineTo(sx2 + spikeW / 2, baseY - 22);
      ctx.lineTo(sx2 + spikeW, baseY);
      ctx.closePath(); ctx.fill();
    }
    // 喷嘴
    ctx.fillStyle = '#888';
    ctx.fillRect(x + 27, y + 174, 27, 10);
    ctx.restore();
  },

  // ===== 飞船（外星飞碟）=====
  ship: function (ctx, s, cam, t) {
    var x = s.x - cam.x, y = s.y + Math.sin(t * 1.5 + (s.bob || 0)) * 4.5;
    var cx = x + s.w / 2;
    ctx.save();
    // 灯光闪烁
    var lit = Math.floor(t * 3) % 2 === 0;
    // 起落架
    ctx.strokeStyle = '#9aa0ad';
    ctx.lineWidth = 4.5;
    ctx.beginPath(); ctx.moveTo(cx - 45, y + 54); ctx.lineTo(cx - 54, y + 78); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx + 45, y + 54); ctx.lineTo(cx + 54, y + 78); ctx.stroke();
    ctx.fillStyle = '#7c828f';
    ctx.beginPath(); ctx.ellipse(cx - 54, y + 78, 7.5, 4.5, 0, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.ellipse(cx + 54, y + 78, 7.5, 4.5, 0, 0, Math.PI * 2); ctx.fill();
    // 飞碟主体
    var g = ctx.createLinearGradient(0, y + 30, 0, y + 66);
    g.addColorStop(0, '#e8edf5');
    g.addColorStop(1, '#9aa0ad');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.ellipse(cx, y + 51, 69, 18, 0, 0, Math.PI * 2);
    ctx.fill();
    // 圆顶
    var g2 = ctx.createLinearGradient(0, y, 0, y + 51);
    g2.addColorStop(0, '#bfe0ff');
    g2.addColorStop(1, '#5aa0e0');
    ctx.fillStyle = g2;
    ctx.beginPath();
    ctx.ellipse(cx, y + 45, 33, 30, 0, Math.PI, 0);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.5)';
    ctx.beginPath(); ctx.ellipse(cx - 12, y + 33, 9, 6, 0, 0, Math.PI * 2); ctx.fill();
    // 底部灯
    ctx.fillStyle = lit ? '#ffe14a' : '#c9a23a';
    for (var i = -3; i <= 3; i++) {
      ctx.beginPath();
      ctx.arc(cx + i * 16.5, y + 60, 3.75, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  },

  // ===== 神秘城堡（开着门、门口发光的卡通城堡）=====
  castle: function (ctx, e, cam, t) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var glow = 0.5 + 0.5 * Math.sin(e.glow * 3);
    ctx.save();
    // 门口的金色光晕（呼吸一样一明一灭）
    ctx.globalAlpha = 0.25 + 0.2 * glow;
    var rg = ctx.createRadialGradient(cx, y + e.h - 40, 10, cx, y + e.h - 40, 120);
    rg.addColorStop(0, '#ffe14a');
    rg.addColorStop(1, 'rgba(255,225,74,0)');
    ctx.fillStyle = rg;
    ctx.beginPath(); ctx.arc(cx, y + e.h - 40, 120, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
    // 左右两座塔楼
    for (var side = -1; side <= 1; side += 2) {
      var tx = cx + side * 105;
      ctx.fillStyle = '#8a8fa0';
      ctx.fillRect(tx - 32, y + 90, 64, e.h - 90);
      // 塔楼红色尖顶
      ctx.fillStyle = '#c84a3a';
      ctx.beginPath();
      ctx.moveTo(tx - 42, y + 90);
      ctx.lineTo(tx, y + 28);
      ctx.lineTo(tx + 42, y + 90);
      ctx.closePath(); ctx.fill();
      // 塔尖小球
      ctx.fillStyle = '#ffd94a';
      ctx.beginPath(); ctx.arc(tx, y + 24, 6, 0, Math.PI * 2); ctx.fill();
      // 塔楼窗户（暖光）
      ctx.fillStyle = '#ffd94a';
      ctx.beginPath();
      ctx.moveTo(tx - 9, y + 150);
      ctx.lineTo(tx - 9, y + 128);
      ctx.arc(tx, y + 128, 9, Math.PI, 0);
      ctx.lineTo(tx + 9, y + 150);
      ctx.closePath(); ctx.fill();
    }
    // 中间主楼
    ctx.fillStyle = '#9aa0b0';
    ctx.fillRect(cx - 80, y + 130, 160, e.h - 130);
    // 城垛
    ctx.fillStyle = '#8a8fa0';
    for (var bi = 0; bi < 5; bi++) {
      ctx.fillRect(cx - 80 + bi * 34, y + 112, 20, 20);
    }
    // 石墙砖缝
    ctx.strokeStyle = 'rgba(0,0,0,0.15)';
    ctx.lineWidth = 2;
    for (var by = y + 160; by < y + e.h - 10; by += 26) {
      ctx.beginPath(); ctx.moveTo(cx - 78, by); ctx.lineTo(cx + 78, by); ctx.stroke();
    }
    // 发光的拱形大门（门开着，里面金光大亮）
    var dg = ctx.createLinearGradient(0, y + e.h - 100, 0, y + e.h);
    dg.addColorStop(0, '#fff2a0');
    dg.addColorStop(1, '#ffb040');
    ctx.fillStyle = dg;
    ctx.beginPath();
    ctx.moveTo(cx - 34, y + e.h);
    ctx.lineTo(cx - 34, y + e.h - 62);
    ctx.arc(cx, y + e.h - 62, 34, Math.PI, 0);
    ctx.lineTo(cx + 34, y + e.h);
    ctx.closePath(); ctx.fill();
    // 门框（深色描边）
    ctx.strokeStyle = '#5a4a3a';
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.moveTo(cx - 37, y + e.h);
    ctx.lineTo(cx - 37, y + e.h - 62);
    ctx.arc(cx, y + e.h - 62, 37, Math.PI, 0);
    ctx.lineTo(cx + 37, y + e.h);
    ctx.stroke();
    // 两扇敞开的木门（贴在门洞两侧）
    ctx.fillStyle = '#7a4a2a';
    ctx.fillRect(cx - 37, y + e.h - 56, 12, 56);
    ctx.fillRect(cx + 25, y + e.h - 56, 12, 56);
    // 门上的「↑ 进入」提示（一闪一闪）
    if (glow > 0.55) {
      this.strokeText(ctx, '↑', cx, y + e.h - 130, 40, '#ffe14a', '#7a5a10', 6);
    }
    ctx.restore();
  },

  // ===== 旗帜 =====
  flag: function (ctx, f, cam, t) {
    var x = f.x - cam.x, y = f.y;
    ctx.strokeStyle = '#bbb';
    ctx.lineWidth = 4.5;
    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y + 105); ctx.stroke();
    var wave = Math.sin(t * 4) * 4.5;
    ctx.fillStyle = '#ff5252';
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + 51, y + 9 + wave);
    ctx.lineTo(x + 42, y + 24);
    ctx.lineTo(x + 51, y + 39 + wave);
    ctx.lineTo(x, y + 33);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(x + 18, y + 19.5, 4.5, 0, Math.PI * 2); ctx.fill();
  },

  particle: function (ctx, p, cam) {
    var a = Math.max(0, p.life / p.maxLife);
    ctx.globalAlpha = a;
    ctx.fillStyle = p.color;
    ctx.fillRect(p.x - cam.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
    ctx.globalAlpha = 1;
  },

  crater: function (ctx, c, cam) {
    ctx.globalAlpha = Math.min(1, c.life);
    ctx.fillStyle = 'rgba(60,60,70,0.5)';
    ctx.beginPath();
    ctx.ellipse(c.x - cam.x, c.y, c.r, c.r * 0.4, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  },

  // ===== HUD =====
  hud: function (ctx, p, score, stageName, muted, game) {
    // 心
    for (var i = 0; i < p.maxHearts; i++) {
      this._heart(ctx, 33 + i * 45, 39, i < p.hearts);
    }
    // 主角名字
    this.text(ctx, '杨御风', 33 + p.maxHearts * 45 + 12, 40, 24, '#cfe0ff', 'left', true);
    // 状态图标（晕 / 慢）
    var iconX = 33 + p.maxHearts * 45 + 92;
    if (p.dizzyT > 0) {
      this.strokeText(ctx, '晕', iconX, 39, 30, '#ffe14a', '#6a3a00', 5);
      iconX += 48;
    }
    if (p.slowT > 0) {
      this.strokeText(ctx, '慢', iconX, 39, 30, '#8de05a', '#1a4a1a', 5);
      iconX += 48;
    }
    // 五种必杀技图标（第 4 幕登船解锁后显示；冷却中会变暗）
    if (p.hasWeapons) {
      var MAXCD = { bullet: 0.15, fireball: 0.5, missile: 0.8, atombomb: 2.5, hydrogenbomb: 5 };
      var KEYS = { bullet: 'H', fireball: 'J', missile: 'K', atombomb: 'L', hydrogenbomb: 'U' };
      var NAMES = { bullet: '子弹', fireball: '火球', missile: '导弹', atombomb: '原子弹', hydrogenbomb: '氢弹' };
      var kinds = ['bullet', 'fireball', 'missile', 'atombomb', 'hydrogenbomb'];
      var wx = 33;
      for (var wi = 0; wi < kinds.length; wi++) {
        var kind = kinds[wi];
        ctx.fillStyle = 'rgba(0,0,0,0.45)';
        Util.roundRect(ctx, wx - 6, 67, 86, 35, 9);
        this._weaponIcon(ctx, wx + 10, 84, kind);
        this.text(ctx, KEYS[kind], wx + 26, 85, 20, '#ffe14a', 'left', true);
        this.text(ctx, NAMES[kind], wx + 44, 86, 16, '#fff', 'left');
        var cd = p.cd && p.cd[kind] > 0 ? p.cd[kind] / MAXCD[kind] : 0;
        if (cd > 0) {
          ctx.fillStyle = 'rgba(0,0,0,' + (0.65 * Math.min(1, cd)) + ')';
          Util.roundRect(ctx, wx - 6, 67, 86, 35, 9);
        }
        wx += 94;
      }
    }
    // 最终 Boss 战：显示阶段 + 队友情况
    var bossRef = null;
    if (game) {
      for (var bi2 = 0; bi2 < game.entities.length; bi2++) {
        if (game.entities[bi2].type === 'timedevourer') { bossRef = game.entities[bi2]; break; }
      }
    }
    if (bossRef) {
      var alliesN = 0;
      for (var ai2 = 0; ai2 < game.entities.length; ai2++) {
        if (game.entities[ai2].type === 'ally' && game.entities[ai2].alive) alliesN++;
      }
      var label = bossRef.phase === 2
        ? ('第二阶段·按 B 召唤队友 ' + alliesN + '/' + MAX_ALLIES)
        : '把光头强打到生气，就能召唤队友！';
      this.strokeText(ctx, label, VIEW.W / 2, VIEW.H - 100, 26,
        bossRef.phase === 2 ? '#ffd94a' : '#9ad0ff', '#000', 5);
    }
    // 第 4 幕：击杀计数 X/60
    var s = game && game.stageIndex < STAGES.length ? STAGES[game.stageIndex] : null;
    if (s && s.needKills) {
      var done = game.killCount >= s.needKills;
      this.strokeText(ctx, '击杀 ' + Math.min(game.killCount, s.needKills) + '/' + s.needKills,
        VIEW.W - 130, 90, 33, done ? '#8de05a' : '#ffe14a', '#000', 6);
    }
    // 分数
    this.strokeText(ctx, '分数 ' + score, VIEW.W - 120, 39, 33, '#fff', '#000', 6);
    // 幕名
    this.strokeText(ctx, stageName, VIEW.W / 2, 39, 30, '#ffe14a', '#000', 6);
    // 静音图标
    if (muted) {
      this.strokeText(ctx, '🔇', VIEW.W - 60, 90, 27, '#fff', '#000', 4);
    }
  },

  // 武器小图标（HUD 与解锁面板共用）
  _weaponIcon: function (ctx, x, y, kind) {
    ctx.save();
    if (kind === 'bullet') {
      ctx.fillStyle = '#ffd94a';
      Util.roundRect(ctx, x - 8, y - 4, 14, 8, 4);
      ctx.fillStyle = '#e8a41a';
      ctx.beginPath(); ctx.moveTo(x + 6, y - 4); ctx.lineTo(x + 11, y); ctx.lineTo(x + 6, y + 4); ctx.closePath(); ctx.fill();
    } else if (kind === 'fireball') {
      ctx.fillStyle = '#ff6a2a';
      ctx.beginPath();
      ctx.moveTo(x, y - 10);
      ctx.bezierCurveTo(x + 8, y - 2, x + 7, y + 8, x, y + 9);
      ctx.bezierCurveTo(x - 7, y + 8, x - 8, y - 2, x, y - 10);
      ctx.fill();
      ctx.fillStyle = '#ffd94a';
      ctx.beginPath(); ctx.arc(x, y + 3, 3.5, 0, Math.PI * 2); ctx.fill();
    } else if (kind === 'missile') {
      ctx.fillStyle = '#e8ecf5';
      Util.roundRect(ctx, x - 9, y - 4, 15, 8, 4);
      ctx.fillStyle = '#d93a3a';
      ctx.beginPath(); ctx.moveTo(x + 6, y - 4); ctx.lineTo(x + 12, y); ctx.lineTo(x + 6, y + 4); ctx.closePath(); ctx.fill();
    } else if (kind === 'atombomb') {
      ctx.fillStyle = '#3a4a2a';
      ctx.beginPath(); ctx.arc(x, y, 8, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#ffd94a';
      ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill();
    } else { // hydrogenbomb
      ctx.fillStyle = '#e8ecf5';
      ctx.beginPath(); ctx.arc(x, y, 8, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = '#5ab0ff';
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(x, y, 10, 0, Math.PI * 2); ctx.stroke();
      ctx.fillStyle = '#2a6fd6';
      ctx.fillRect(x - 2, y - 5, 4, 10);
    }
    ctx.restore();
  },

  _heart: function (ctx, x, y, full) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(1.5, 1.5);
    ctx.fillStyle = full ? '#ff4d6d' : '#5a3030';
    ctx.beginPath();
    ctx.moveTo(0, 4);
    ctx.bezierCurveTo(-8, -6, -10, 6, 0, 12);
    ctx.bezierCurveTo(10, 6, 8, -6, 0, 4);
    ctx.fill();
    ctx.restore();
  },

  tipBar: function (ctx, tip) {
    if (!tip) return;
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    Util.roundRect(ctx, VIEW.W / 2 - 420, VIEW.H - 68, 840, 50, 12);
    this.text(ctx, tip, VIEW.W / 2, VIEW.H - 43, 25, '#fff', 'center');
  },

  // ===== 菜单 =====
  menu: function (ctx, t) {
    var g = ctx.createLinearGradient(0, 0, 0, VIEW.H);
    g.addColorStop(0, '#0b1030');
    g.addColorStop(1, '#2a1030');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, VIEW.W, VIEW.H);
    // 星
    ctx.fillStyle = '#fff';
    for (var i = 0; i < 90; i++) {
      var sx = (i * 137.5) % VIEW.W;
      var sy = (i * 73.3) % VIEW.H;
      var tw = 0.3 + 0.7 * Math.abs(Math.sin(t * 1.5 + i));
      ctx.globalAlpha = tw * 0.8;
      ctx.fillRect(sx, sy, 3, 3);
    }
    ctx.globalAlpha = 1;
    // 远处大大的火星（红色星球）
    ctx.fillStyle = '#c85a3a';
    ctx.beginPath(); ctx.arc(1140, 570, 135, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#a8442c';
    ctx.beginPath(); ctx.arc(1100, 530, 40, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(1195, 610, 30, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(255,200,150,0.25)';
    ctx.beginPath(); ctx.arc(1100, 520, 135 * 0.95, Math.PI * 1.15, Math.PI * 1.6); ctx.stroke();

    // 标题
    this.strokeText(ctx, '杨御风：火星远征', VIEW.W / 2, 225, 96, '#ffe14a', '#6a1a3a', 12);
    this.text(ctx, '🚀 太空战士杨御风的火星大冒险 🚀', VIEW.W / 2, 310, 27, '#ffd0c0', 'center');

    // 小小的杨御风
    var demoP = { x: 690, y: 420, w: 39, h: 63, facing: 1, vx: 1, onGround: true, anim: t * 8, invincible: 0, dizzyT: 0 };
    this.player(ctx, demoP, { x: 0, y: 0 });

    // 按键说明
    ctx.fillStyle = 'rgba(0,0,0,0.4)';
    Util.roundRect(ctx, 345, 525, 750, 200, 18);
    this.text(ctx, '← / → 或 A / D  移动        空格 / W / ↑  跳跃', VIEW.W / 2, 563, 26, '#fff', 'center');
    this.text(ctx, '↑  进入火箭 / 飞船 / 城堡大门', VIEW.W / 2, 603, 26, '#fff', 'center');
    this.text(ctx, 'H 子弹  J 火球  K 大导弹  L 原子弹  U 氢弹（第 4 幕登船解锁）', VIEW.W / 2, 643, 24, '#ffd94a', 'center');
    this.text(ctx, 'P 暂停      M 静音', VIEW.W / 2, 683, 24, '#cfe0ff', 'center');
    // 闪烁开始提示
    if (Math.floor(t * 2) % 2 === 0) {
      this.strokeText(ctx, '按 空格 或 回车 开始', VIEW.W / 2, 770, 33, '#fff', '#000', 6);
    }
  },

  // ===== 暂停 =====
  pause: function (ctx) {
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.fillRect(0, 0, VIEW.W, VIEW.H);
    this.strokeText(ctx, '已暂停', VIEW.W / 2, 375, 84, '#fff', '#000', 9);
    this.text(ctx, '按 P 或 Esc 继续', VIEW.W / 2, 465, 30, '#cfe0ff', 'center');
  },

  // ===== 失败 =====
  gameover: function (ctx, score, t) {
    ctx.fillStyle = 'rgba(0,0,0,0.65)';
    ctx.fillRect(0, 0, VIEW.W, VIEW.H);
    this.strokeText(ctx, '再试一次！', VIEW.W / 2, 300, 84, '#ff8a8a', '#000', 9);
    this.text(ctx, '杨御风摔疼了，没关系，再来一次～', VIEW.W / 2, 405, 30, '#fff', 'center');
    this.strokeText(ctx, '分数 ' + score, VIEW.W / 2, 480, 42, '#ffe14a', '#000', 6);
    if (Math.floor(t * 2) % 2 === 0) {
      this.strokeText(ctx, '按 空格 或 回车 重新开始', VIEW.W / 2, 600, 33, '#fff', '#000', 6);
    }
  },

  // ===== 胜利 =====
  win: function (ctx, score, t) {
    // 地球草地背景
    var g = ctx.createLinearGradient(0, 0, 0, VIEW.H);
    g.addColorStop(0, '#6fb6ff');
    g.addColorStop(0.7, '#cfeaff');
    g.addColorStop(1, '#9be08a');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, VIEW.W, VIEW.H);
    // 太阳
    ctx.fillStyle = 'rgba(255,255,200,0.8)';
    ctx.beginPath(); ctx.arc(180, 150, 75, 0, Math.PI * 2); ctx.fill();
    // 云
    this._cloud(ctx, 375, 180);
    this._cloud(ctx, 1050, 135);
    this._cloud(ctx, 815, 270);
    // 草地
    ctx.fillStyle = '#5fbf4a';
    ctx.fillRect(0, 660, VIEW.W, 150);
    ctx.fillStyle = '#3a9a32';
    for (var i = 0; i < 40; i++) {
      ctx.fillRect(i * 36 + 6, 660, 4.5, 12);
      ctx.fillRect(i * 36 + 12, 660, 4.5, 15);
    }
    // 站在草地上的杨御风
    var bob = Math.sin(t * 2) * 4.5;
    var demoP = { x: 690, y: 597 + bob, w: 39, h: 63, facing: 1, vx: 0, onGround: true, anim: 0, invincible: 0, dizzyT: 0 };
    this.player(ctx, demoP, { x: 0, y: 0 });
    // 文字
    this.strokeText(ctx, '通关！', VIEW.W / 2, 225, 84, '#ffe14a', '#3a6a1a', 12);
    this.strokeText(ctx, '杨御风平安回到了地球 🌍', VIEW.W / 2, 322, 42, '#fff', '#3a6a1a', 7);
    this.strokeText(ctx, '总分 ' + score, VIEW.W / 2, 495, 51, '#fff', '#3a6a1a', 7);
    if (Math.floor(t * 2) % 2 === 0) {
      this.strokeText(ctx, '按 空格 或 回车 再玩一次', VIEW.W / 2, 585, 33, '#fff', '#3a6a1a', 7);
    }
  },

  // ===== Boss 胜利小节 =====
  bossClear: function (ctx, clearT, t, name) {
    var a = Math.min(1, (2.0 - clearT) * 3);   // 淡入
    ctx.save();
    ctx.globalAlpha = a;
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.fillRect(0, 300, VIEW.W, 130);
    this.strokeText(ctx, '打败了' + (name || '大魔王') + '！', VIEW.W / 2, 365 + Math.sin(t * 6) * 4, 54, '#ffe14a', '#6a1a3a', 9);
    ctx.restore();
  },

  // ===== 宇航员队友（被召唤来一起打光头强）=====
  ally: function (ctx, e, cam) {
    var x = e.x - cam.x, y = e.y;
    var cx = x + e.w / 2;
    var moving = e.onGround && Math.abs(e.vx) > 0.6;
    var swing = moving ? Math.sin(e.anim) : 0;
    ctx.save();
    if (!e.alive) {
      // 倒下：绕脚躺平 + 变淡
      var fall = Math.min(1, e.deadT / 0.4);
      ctx.translate(cx, y + e.h);
      ctx.rotate((e.side >= 0 ? 1 : -1) * fall * 1.5);
      ctx.globalAlpha = Math.max(0.25, 1 - e.deadT * 1.6);
      ctx.translate(-cx, -(y + e.h));
    } else if (e.invincible > 0 && Math.floor(e.invincible * 16) % 2 === 0) {
      ctx.restore();
      return;   // 无敌闪烁
    }
    var suit = e.suit || '#3a6fd9';
    var trim = e.trim || '#aadcff';
    // 背包
    ctx.fillStyle = '#222a44';
    Util.roundRect(ctx, x + (e.facing < 0 ? 18 : 3), y + 24, 18, 33, 6);
    // 腿
    ctx.fillStyle = '#2a2f44';
    ctx.fillRect(x + 9 + swing * 4.5, y + 51, 9, 13.5);
    ctx.fillRect(x + 21 - swing * 4.5, y + 51, 9, 13.5);
    // 靴
    ctx.fillStyle = trim;
    ctx.fillRect(x + 7.5 + swing * 4.5, y + 61.5, 12, 4.5);
    ctx.fillRect(x + 19.5 - swing * 4.5, y + 61.5, 12, 4.5);
    // 身体
    ctx.fillStyle = suit;
    Util.roundRect(ctx, x + 6, y + 24, 27, 30, 9);
    // 白色胸甲 + 护心
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(cx, y + 39, 6, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = trim;
    ctx.beginPath(); ctx.arc(cx, y + 39, 3, 0, Math.PI * 2); ctx.fill();
    // 手臂
    ctx.fillStyle = suit;
    ctx.fillRect(x + 1.5, y + 27 - swing * 3, 7.5, 18);
    ctx.fillRect(x + 30, y + 27 + swing * 3, 7.5, 18);
    ctx.fillStyle = '#f0c8a0';
    ctx.beginPath(); ctx.arc(x + 5, y + 46 - swing * 3, 4, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 34, y + 46 + swing * 3, 4, 0, Math.PI * 2); ctx.fill();
    // 脸
    ctx.fillStyle = '#f0c8a0';
    ctx.beginPath(); ctx.arc(cx, y + 15, 12, 0, Math.PI * 2); ctx.fill();
    if (e.alive) {
      ctx.fillStyle = '#1a1a1a';
      ctx.beginPath(); ctx.arc(cx - 4 + e.facing * 2, y + 13, 2, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.arc(cx + 4 + e.facing * 2, y + 13, 2, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = '#8a5a3a'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.arc(cx + e.facing, y + 18, 4, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    } else {
      // X 眼（被打倒）
      ctx.strokeStyle = '#5a3030'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(cx - 6, y + 11); ctx.lineTo(cx - 2, y + 15);
      ctx.moveTo(cx - 2, y + 11); ctx.lineTo(cx - 6, y + 15); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(cx + 2, y + 11); ctx.lineTo(cx + 6, y + 15);
      ctx.moveTo(cx + 6, y + 11); ctx.lineTo(cx + 2, y + 15); ctx.stroke();
    }
    // 透明头盔
    ctx.fillStyle = 'rgba(180,230,255,0.28)';
    ctx.beginPath(); ctx.arc(cx, y + 15, 18, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = trim; ctx.lineWidth = 2.25; ctx.stroke();
    // 名字牌
    this.text(ctx, e.name || '队友', cx, y - 8, 16, '#fff', 'center', true);
    // 小血条
    if (e.alive && e.maxHearts) {
      var bw2 = 30, bx2 = cx - bw2 / 2, by2 = y - 24;
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      Util.roundRect(ctx, bx2 - 2, by2 - 2, bw2 + 4, 8, 3);
      ctx.fillStyle = '#3a2a2a';
      Util.roundRect(ctx, bx2, by2, bw2, 4, 2);
      ctx.fillStyle = '#5ad06a';
      Util.roundRect(ctx, bx2, by2, Math.max(2, bw2 * (e.hearts / e.maxHearts)), 4, 2);
    }
    ctx.restore();
  },

  // ===== 光头强进入第二阶段横幅 =====
  phaseBanner: function (ctx, t) {
    var a = Math.min(1, Math.min(t / 0.4, (2.4 - t) / 0.4) + 0.2);
    ctx.save();
    ctx.globalAlpha = a;
    ctx.fillStyle = 'rgba(120,10,10,0.55)';
    ctx.fillRect(0, 250, VIEW.W, 150);
    this.strokeText(ctx, '光头强生气了！', VIEW.W / 2, 300, 64, '#ff5a3a', '#2a0000', 10);
    this.strokeText(ctx, '第二阶段 · 按 B 召唤宇航员队友一起打！', VIEW.W / 2, 372, 32, '#ffe14a', '#2a0000', 7);
    ctx.restore();
  },

  // ===== 召唤提示 / 消息 toast =====
  toast: function (ctx, msg) {
    ctx.save();
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    Util.roundRect(ctx, VIEW.W / 2 - 340, 118, 680, 54, 12);
    this.text(ctx, msg, VIEW.W / 2, 145, 26, '#fff', 'center', true);
    ctx.restore();
  },

  // ===== 过场：火箭发射（地球 → 太空）=====
  cutsceneLaunch: function (ctx, prog, stage, cam, t, stars, shake) {
    // 天空由地球蓝天渐变到太空黑
    var blend = Util.clamp(prog * 1.3, 0, 1);
    this.background(ctx, stage, cam, t, stars, { themeOverride: 'earth', blend: blend });
    // 火箭已升空：在屏幕中央偏上
    var r = { x: VIEW.W / 2 - 40.5, y: VIEW.H * 2 / 3 - prog * 780, w: 81, h: 180, flameT: 1 };
    ctx.save();
    if (shake) {
      ctx.translate(Util.rand(-shake, shake), Util.rand(-shake, shake));
    }
    this.rocket(ctx, r, { x: 0, y: 0 }, t);
    ctx.restore();
    // 提示
    if (prog > 0.3) {
      this.strokeText(ctx, '发射！杨御风飞向月球…', VIEW.W / 2, 705, 42, '#fff', '#000', 7);
    }
  },

  // ===== 过场：登船去火星（途中解锁全部五种必杀技）=====
  cutsceneToMars: function (ctx, prog, t, shake) {
    var W = VIEW.W, H = VIEW.H;
    // 太空背景
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#070a1f');
    g.addColorStop(1, '#1a1f3a');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = '#fff';
    for (var i = 0; i < 60; i++) {
      var tw = 0.4 + 0.6 * Math.abs(Math.sin(t * 2 + i));
      ctx.globalAlpha = tw;
      ctx.fillRect((i * 137) % W, (i * 71) % H, 3, 3);
    }
    ctx.globalAlpha = 1;
    // 火星由小变大（越来越近了！）
    var mr = 40 + prog * 300;
    var mx = W * 0.72, my = H * 0.4;
    ctx.fillStyle = '#c85a3a';
    ctx.beginPath(); ctx.arc(mx, my, mr, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#a8442c';
    ctx.beginPath(); ctx.arc(mx - mr * 0.3, my - mr * 0.2, mr * 0.32, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(mx + mr * 0.35, my + mr * 0.25, mr * 0.22, 0, Math.PI * 2); ctx.fill();
    // 飞船从左下朝火星飞去
    var sx = W * 0.2 + prog * W * 0.3;
    var sy = H * 0.85 - prog * H * 0.4;
    ctx.save();
    if (shake) ctx.translate(Util.rand(-shake, shake), Util.rand(-shake, shake));
    this.ship(ctx, { x: sx - 72, y: sy, w: 144, h: 90, bob: 0 }, { x: 0, y: 0 }, t);
    ctx.restore();
    if (prog < 0.5) {
      this.strokeText(ctx, '登船！出发去火星…', W / 2, 90, 42, '#fff', '#000', 7);
    } else {
      // 解锁面板：五种必杀技一次全给！
      var a = Math.min(1, (prog - 0.5) * 5);
      ctx.save();
      ctx.globalAlpha = a;
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      Util.roundRect(ctx, W / 2 - 330, 180, 660, 420, 20);
      this.strokeText(ctx, '⭐ 解锁全部必杀技！⭐', W / 2, 240, 48, '#ffe14a', '#6a3a00', 8);
      var ROWS = [
        ['bullet', 'H', '子弹：最快的小弹丸'],
        ['fireball', 'J', '火球：会弹跳的火焰球'],
        ['missile', 'K', '大导弹：又快又猛'],
        ['atombomb', 'L', '原子弹：炸开一大片'],
        ['hydrogenbomb', 'U', '氢弹：最——大——的爆炸！']
      ];
      for (var ri = 0; ri < ROWS.length; ri++) {
        var ry = 310 + ri * 56;
        this._weaponIcon(ctx, W / 2 - 230, ry, ROWS[ri][0]);
        this.text(ctx, ROWS[ri][1], W / 2 - 195, ry + 1, 26, '#ffe14a', 'left', true);
        this.text(ctx, ROWS[ri][2], W / 2 - 150, ry + 1, 25, '#fff', 'left');
      }
      ctx.restore();
    }
  },

  // ===== 过场：走进城堡（画面渐黑）=====
  cutsceneEnterCastle: function (ctx, prog, t) {
    var a = Util.clamp(prog * 1.3, 0, 1);
    ctx.fillStyle = 'rgba(0,0,0,' + a + ')';
    ctx.fillRect(0, 0, VIEW.W, VIEW.H);
    if (prog > 0.25) {
      ctx.save();
      ctx.globalAlpha = Math.min(1, (prog - 0.25) * 3);
      this.strokeText(ctx, '走进神秘的城堡…', VIEW.W / 2, VIEW.H / 2, 48, '#e0c8ff', '#000', 8);
      ctx.restore();
    }
  },

  // ===== 过场：打败最终 Boss，乘外星飞船飞回地球 =====
  cutsceneReturn: function (ctx, prog, t, shake) {
    // 阶段：0~0.4 飞离火星；0.4~0.75 地球由小变大；0.75~1.0 穿云降落
    var H = VIEW.H, W = VIEW.W;
    if (prog < 0.4) {
      // 月球天空 + 飞船上升
      var g = ctx.createLinearGradient(0, 0, 0, H);
      g.addColorStop(0, '#10131f'); g.addColorStop(1, '#3a3550');
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = '#fff';
      for (var i = 0; i < 60; i++) ctx.fillRect((i * 137) % W, (i * 71) % H, 3, 3);
      // 月球地表（逐渐下移消失）
      var marsY = 693 + prog * 600;
      ctx.fillStyle = '#9a93a0'; ctx.fillRect(0, marsY, W, H - marsY);
      // 飞船上升
      var sy = H * 2 / 3 - prog * 900;
      ctx.save();
      if (shake) ctx.translate(Util.rand(-shake, shake), Util.rand(-shake, shake));
      this.ship(ctx, { x: W / 2 - 72, y: sy, w: 144, h: 90, bob: 0 }, { x: 0, y: 0 }, t);
      ctx.restore();
      this.strokeText(ctx, '飞船飞离月球…', W / 2, 90, 39, '#fff', '#000', 6);
    } else if (prog < 0.75) {
      // 太空 -> 地球由小变大
      var p2 = (prog - 0.4) / 0.35;
      var g2 = ctx.createLinearGradient(0, 0, 0, H);
      g2.addColorStop(0, this._mix('#070a1f', '#6fb6ff', p2));
      g2.addColorStop(1, this._mix('#1a1f3a', '#cfeaff', p2));
      ctx.fillStyle = g2; ctx.fillRect(0, 0, W, H);
      // 地球
      var er = 30 + p2 * 330;
      var ex = W / 2, ey = H / 2;
      ctx.fillStyle = '#2a6fd6';
      ctx.beginPath(); ctx.arc(ex, ey, er, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#3aa856';
      ctx.beginPath(); ctx.arc(ex - er * 0.3, ey - er * 0.2, er * 0.4, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.arc(ex + er * 0.35, ey + er * 0.25, er * 0.3, 0, Math.PI * 2); ctx.fill();
      // 飞船向地球飞
      var sx = W / 2, sy2 = 630 - p2 * 450;
      this.ship(ctx, { x: sx - 72, y: sy2, w: 144, h: 90, bob: 0 }, { x: 0, y: 0 }, t);
      this.strokeText(ctx, '回家啦！飞向地球…', W / 2, 75, 39, '#fff', '#000', 6);
    } else {
      // 穿云降落草地
      var p3 = (prog - 0.75) / 0.25;
      var g3 = ctx.createLinearGradient(0, 0, 0, H);
      g3.addColorStop(0, '#6fb6ff'); g3.addColorStop(1, '#cfeaff');
      ctx.fillStyle = g3; ctx.fillRect(0, 0, W, H);
      this._cloud(ctx, 300, 180 + p3 * 120);
      this._cloud(ctx, 1050, 135 + p3 * 180);
      ctx.fillStyle = '#5fbf4a'; ctx.fillRect(0, 693 - (1 - p3) * 300, W, H);
      var sy3 = 300 + p3 * 300;
      ctx.save();
      if (shake) ctx.translate(Util.rand(-shake, shake), Util.rand(-shake, shake));
      this.ship(ctx, { x: W / 2 - 72, y: sy3, w: 144, h: 90, bob: 0 }, { x: 0, y: 0 }, t);
      ctx.restore();
      this.strokeText(ctx, '穿过云层，降落地球…', W / 2, 75, 39, '#fff', '#000', 6);
    }
  }
};
