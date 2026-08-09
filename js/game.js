// game.js - 主循环与状态机
// 所有 DOM/Canvas 访问集中在 init()；step(dt) 可在无 Canvas 环境下被测试逐帧驱动

// 物理常量（按 60fps 一帧标定，step 内用 f=dt*60 缩放）
var G_MOVE = 4.8, G_ACCEL = 1.2, G_FRICTION = 0.9, G_MAX_FALL = 24;

// 普通怪兽被武器命中时的 [得分, 尘土颜色]（命中即消灭）
var SHOOTABLE = {
  spiderling: [50, '#cbb3c8'],
  poopbeast: [100, '#7a4a22'],
  snotbeast: [150, '#a8c84a'],
  sockbeast: [150, '#7a8aaa'],
  hornbeast: [100, '#e07830'],
  rollbeast: [150, '#3aa8a0'],
  snotworm: [50, '#b8d84a'],
  littlesnake: [80, '#9ad04a']
};

// 五种必杀技的直接命中伤害（原子弹/氢弹的伤害由爆炸 AoE 结算）
var WEAPON_DMG = { bullet: 1, fireball: 3, missile: 6 };

// 最终 Boss 两阶段：血量降到此比例 → 进入第二阶段（光头强生气，攻击明显变猛）
var BOSS_PHASE2_FRAC = 0.5;
var MAX_ALLIES = 2;            // 最多同时召唤的宇航员队友数（飞飞、童童）
var SUMMON_CD = 0.7;           // 召唤冷却（秒），避免一次按出一群

// 可玩幕为 idx 0~16（共 17 幕）：原版火星主线 8 幕 + 月球续集 6 幕 + 蛇山之路/帝王蛇怪/三头帝王蛇 3 幕
// 到 idx 17 进 win（「飞回地球」是返航过场 + 胜利画面）
var LAST_STAGE = 17;

function Game() {
  this.canvas = null;
  this.ctx = null;
  this.state = 'menu';            // menu | playing | cutscene | gameover | win
  this.stageIndex = 0;
  this.player = null;
  this.entities = [];
  this.platforms = [];
  this.camera = { x: 0, y: 0 };
  this.shake = 0;
  this.flashAlpha = 0;
  this.time = 0;
  this.score = 0;
  this.paused = false;
  this.muted = false;
  this.cutscene = null;
  this.snowRollAcc = 0;
  this.snowFallAcc = 0;
  this.houseAcc = 0;
  this.hornT = 0;                 // 长角兽出场计时（第 4 幕）
  this.rollT = 0;                 // 滚球兽出场计时（第 4 幕）
  this.killCount = 0;             // 第 4 幕踩扁长角兽计数（HUD 显示 X/60）
  this.hasWeapons = false;        // 五种必杀技（第 4 幕登船解锁，跨关保留，存在 Game 上）
  this.bossHp = {};               // Boss 剩余血量（按幕记录）：跨死亡重来保留（不惩罚小朋友辛苦削的血）
  this.bossClearT = 0;            // >0：Boss 已被打死，胜利小节倒计时
  this.bossClearName = '';
  this.phaseBannerT = 0;         // >0：Boss 进入第二阶段横幅倒计时
  this.phaseBannerMsg = '';       // 第二阶段横幅的标题（按 Boss 类型区分）
  this.summonCd = 0;             // 召唤冷却
  this.summonMsg = '';           // 召唤提示（如「先打到生气」）
  this.summonMsgT = 0;           // 提示显示倒计时
  this._shipSpawned = false;      // 第 4 幕：飞船是否已降落
  this._shipLanded = false;       // 第 4 幕：飞船是否已停稳
  this.lastTime = 0;
  this._rafId = 0;
  this.bgStars = this._makeStars();
}

Game.prototype._makeStars = function () {
  var arr = [];
  for (var i = 0; i < 135; i++) {
    arr.push({ x: Math.random() * VIEW.W, y: Math.random() * 630, ph: Math.random() * 6.28, big: Math.random() < 0.2 });
  }
  return arr;
};

// ===== 初始化（DOM/Canvas 访问集中于此）=====
Game.prototype.init = function (canvas) {
  this.canvas = canvas;
  this.ctx = canvas.getContext ? canvas.getContext('2d') : null;
  Input.init(typeof window !== 'undefined' ? window : null);
  Sfx.init();
  this.lastTime = 0;
  var self = this;
  var raf = (typeof window !== 'undefined' && window.requestAnimationFrame)
    ? function (cb) { return window.requestAnimationFrame(cb); }
    : function (cb) { return setTimeout(function () { cb(performance.now()); }, 16); };
  this._raf = raf;
  this._rafId = raf(function (t) { self.loop(t); });
};

Game.prototype.loop = function (t) {
  if (!this.lastTime) this.lastTime = t;
  var dt = (t - this.lastTime) / 1000;
  this.lastTime = t;
  if (dt > 0.05) dt = 0.05;     // 防止切屏后大跳
  if (dt < 0) dt = 0;
  this.step(dt);
  this.draw();
  var self = this;
  this._rafId = this._raf(function (u) { self.loop(u); });
};

// ===== 编程输入接口（与键盘监听共用 Input 状态）=====
Game.prototype.pressKey = function (code) { Input.pressKey(code); };
Game.prototype.releaseKey = function (code) { Input.releaseKey(code); };

// ===== 作弊 / 测试辅助 =====
Game.prototype.debugGotoStage = function (n) {
  if (n >= LAST_STAGE) { this.goWin(); return; }
  this.bossHp = {};           // 显式跳关 = 全新进入该幕，Boss 满血（death-retry 才续血）
  this.killCount = 0;
  this.hasWeapons = (n >= 4); // 剧情上：第 4 幕登船（长角兽军团）后才解锁必杀技
  this.loadStage(n);
  this.state = 'playing';
};

Game.prototype.startNewGame = function () {
  this.score = 0;
  this.hasWeapons = false;
  this.killCount = 0;
  this.bossHp = {};
  this.loadStage(0);
  this.state = 'playing';
  this.paused = false;
};

Game.prototype.retry = function () {
  this.loadStage(this.stageIndex);
  this.state = 'playing';
  this.paused = false;
};

Game.prototype.goWin = function () {
  this.stageIndex = LAST_STAGE;
  this.state = 'win';
  Sfx.win();
};

// ===== 关卡装载 =====
Game.prototype.loadStage = function (i) {
  if (i >= LAST_STAGE) { this.goWin(); return; }
  this.stageIndex = i;
  var s = STAGES[i];
  this.player = Entities.player(s.spawn.x, s.spawn.y);
  // 必杀技跨关保留：loadStage 会 new 一个新玩家，把 Game 上的能力回填进去
  this.player.hasWeapons = this.hasWeapons;
  this.entities = [];
  if (s.rocket) this.entities.push(Entities.rocket(s.rocket.x, s.rocket.y));
  // 装饰旗（不触发过关，仅作为场景路标）
  if (s.flags) {
    for (k = 0; k < s.flags.length; k++) {
      var df = Entities.flag(s.flags[k].x, s.flags[k].y);
      df.goalFlag = false;
      this.entities.push(df);
    }
  }
  // 过关旗（碰到即进入下一幕）
  if (s.flag) {
    var gf = Entities.flag(s.flag.x, s.flag.y);
    gf.goalFlag = true;
    this.entities.push(gf);
  }
  if (s.castle) this.entities.push(Entities.castle(s.castle.x, s.groundY));
  // 第 4 幕的飞船要等踩够 60 只长角兽才降落（见 _spawnBeasts 之后的检查）
  if (s.ship && !s.needKills) this.entities.push(Entities.ship(s.ship.x, s.ship.y));
  var k;
  for (k = 0; k < s.poopBeasts.length; k++) {
    var pb = s.poopBeasts[k];
    this.entities.push(Entities.poopbeast(pb[0], pb[1], s.groundY));
  }
  for (k = 0; k < s.snotBeasts.length; k++) {
    this.entities.push(Entities.snotbeast(s.snotBeasts[k], s.groundY));
  }
  for (k = 0; k < s.sockBeasts.length; k++) {
    var sb = s.sockBeasts[k];
    this.entities.push(Entities.sockbeast(sb[0], sb[1], s.groundY));
  }
  for (k = 0; k < s.hornBeasts.length; k++) {
    this.entities.push(Entities.hornbeast(s.hornBeasts[k], s.groundY));
  }
  for (k = 0; k < s.snotWorms.length; k++) {
    var sw = s.snotWorms[k];
    this.entities.push(Entities.snotworm(sw[0], sw[1], s.groundY));
  }
  // 蛇山之路：小蛇阻碍（可带 big:true 作为「蛇将」）
  for (k = 0; k < (s.littleSnakes || []).length; k++) {
    var ls = s.littleSnakes[k];
    this.entities.push(Entities.littlesnake(ls[0], ls[1], s.groundY, ls[2] || {}));
  }
  // 关卡预设的黏液：长期存在
  for (k = 0; k < s.slimes.length; k++) {
    this.entities.push(Entities.slime(s.slimes[k] - 45, s.groundY - 14, 9999));
  }
  // Boss 幕：大蜘蛛兽 / 中级蜘蛛兽 / 魔鬼兽 / 大螃蟹兽 / 巨化光头强
  if (s.boss) {
    var bt = s.boss.kind;
    var b = bt === 'timedevourer' ? Entities.timedevourer(s.boss.x, s.groundY)
      : bt === 'gianttimedevourer' ? Entities.gianttimedevourer(s.boss.x, s.groundY)
      : bt === 'devilbeast' ? Entities.devilbeast(s.boss.x, s.groundY)
      : bt === 'crabbeast' ? Entities.crabbeast(s.boss.x, s.groundY)
      : bt === 'midspider' ? Entities.midspider(s.boss.x, s.groundY)
      : bt === 'emperorsnake' ? Entities.emperorsnake(s.boss.x, s.groundY)
      : bt === 'threeheadsnake' ? Entities.threeheadsnake(s.boss.x, s.groundY)
      : Entities.spiderboss(s.boss.x, s.groundY);
    // 死亡重来时接着上次的残血打（bossHp 按幕记录，首次进关为满血）
    var saved = this.bossHp[i];
    if (saved != null && saved > 0) b.hp = saved;
    this.bossHp[i] = b.hp;
    this.entities.push(b);
  }
  this.platforms = s.platforms;
  this.camera = { x: 0, y: 0 };
  this.snowRollAcc = 0;
  this.snowFallAcc = 0;
  this.houseAcc = 0;
  this.hornT = 1.2;
  this.rollT = 3.0;
  this._shipSpawned = false;
  this._shipLanded = false;
  this.shake = 0;
  this.flashAlpha = 0.6;
  this.bossClearT = 0;
  this.phaseBannerT = 0;
  this.summonCd = 0;
  this.summonMsg = '';
  this.summonMsgT = 0;
  this.cutscene = null;
};

// ===== 单帧推进 =====
Game.prototype.step = function (dt) {
  this.time += dt;
  if (this.shake > 0) this.shake = Math.max(0, this.shake - dt * 8);
  if (this.flashAlpha > 0) this.flashAlpha = Math.max(0, this.flashAlpha - dt * 2.5);

  if (this.state === 'playing' && !this.paused) {
    this.updatePlaying(dt);
  } else if (this.state === 'cutscene') {
    this.updateCutscene(dt);
  } else if (this.state === 'menu') {
    if (Input.actionPressed('start') || Input.actionPressed('jump')) this.startNewGame();
  } else if (this.state === 'gameover') {
    if (Input.actionPressed('start') || Input.actionPressed('jump')) this.retry();
  } else if (this.state === 'win') {
    if (Input.actionPressed('start') || Input.actionPressed('jump')) this.startNewGame();
  }

  // 全局开关
  if (Input.actionPressed('pause') && this.state === 'playing') this.paused = !this.paused;
  if (Input.actionPressed('mute')) { this.muted = !this.muted; Sfx.setEnabled(!this.muted); }

  Input.endFrame();
};

Game.prototype.updatePlaying = function (dt) {
  var f = Util.clamp(dt * 60, 0, 2.5);
  var s = STAGES[this.stageIndex];
  var p = this.player;
  p.anim += dt * 10;

  if (p.invincible > 0) p.invincible = Math.max(0, p.invincible - dt);

  // ----- 状态效果：减速（踩黏液）/ 晕眩（吸臭气）-----
  if (p.slowT > 0) {
    p.slowT = Math.max(0, p.slowT - dt);
    // 脚下冒绿泡提示
    p.bubbleAcc += dt;
    if (p.bubbleAcc > 0.12) {
      p.bubbleAcc = 0;
      this.entities.push(Entities.particle(p.x + Util.rand(6, p.w - 6), p.y + p.h - 6, {
        vx: Util.rand(-0.6, 0.6), vy: Util.rand(-2.4, -1.2), life: 0.5,
        color: '#8de05a', size: Util.randInt(3, 6), gravity: -0.04
      }));
    }
  }
  if (p.dizzyT > 0) p.dizzyT = Math.max(0, p.dizzyT - dt);

  // ----- 五种必杀技各自的冷却 -----
  for (var wk in p.cd) {
    if (p.cd[wk] > 0) p.cd[wk] = Math.max(0, p.cd[wk] - dt);
  }

  // ----- 交互（火箭/飞船/城堡大门），优先于跳跃 -----
  var interactUsed = false;
  if (s.goal === 'rocket' || s.goal === 'ship' || s.goal === 'castle') {
    var target = this._interactTarget(s);
    if (target && Input.actionPressed('interact')) {
      this._startInteractCutscene(s.goal, target);
      interactUsed = true;
    }
  }

  // ----- 输入：移动（晕眩时左右反向）-----
  // 被蛇怪「缠绕卷死」抓住时锁定一切操作，位置由蛇 AI 接管
  if (!p.grabbed) {
  var move = 0;
  if (Input.action('left')) move -= 1;
  if (Input.action('right')) move += 1;
  if (p.dizzyT > 0) move = -move;
  var maxSpd = p.slowT > 0 ? G_MOVE * 0.5 : G_MOVE;
  if (move !== 0) {
    p.vx = Util.approach(p.vx, move * maxSpd, G_ACCEL * f);
    p.facing = move;
  } else {
    p.vx = Util.approach(p.vx, 0, G_FRICTION * f);
  }

  // ----- 跳跃（减速时跳得矮）-----
  if (!interactUsed && Input.actionPressed('jump') && p.onGround) {
    p.vy = -s.jumpVel * (p.slowT > 0 ? 0.72 : 1);
    p.onGround = false;
    p.jumpCut = false;
    Sfx.jump();
  }
  // 跳跃截断：松手则降低上升速度（更好控制高度）
  if (!Input.action('jump') && p.vy < -6 && !p.jumpCut) {
    p.vy *= 0.55;
    p.jumpCut = true;
  }

  // ----- 五种必杀技：H 子弹 / J 火球 / K 大导弹 / L 原子弹 / U 氢弹 -----
  // （第 4 幕登船后一次性全部解锁；未解锁前按键无效；大威力武器靠冷却限制，不做弹药上限）
  if (p.hasWeapons) {
    if (Input.actionPressed('bullet') && p.cd.bullet <= 0) {
      p.cd.bullet = 0.15;
      this.entities.push(Entities.bullet(p.facing > 0 ? p.x + p.w - 2 : p.x - 18, p.y + 22, p.facing));
      Sfx.shoot();
    }
    if (Input.actionPressed('fireball') && p.cd.fireball <= 0) {
      p.cd.fireball = 0.5;
      this.entities.push(Entities.fireball(p.facing > 0 ? p.x + p.w - 2 : p.x - 26, p.y + 12, p.facing));
      Sfx.fireball();
    }
    if (Input.actionPressed('missile') && p.cd.missile <= 0) {
      p.cd.missile = 0.8;
      this.entities.push(Entities.missile(p.facing > 0 ? p.x + p.w - 2 : p.x - 44, p.y + 18, p.facing));
      Sfx.missile();
    }
    if (Input.actionPressed('atombomb') && p.cd.atombomb <= 0) {
      p.cd.atombomb = 2.5;
      this.entities.push(Entities.atombomb(p.x + p.w / 2 - 15 + p.facing * 12, p.y + 4, p.facing));
      Sfx.bombThrow();
    }
    if (Input.actionPressed('hydrogenbomb') && p.cd.hydrogenbomb <= 0) {
      p.cd.hydrogenbomb = 5.0;
      this.entities.push(Entities.hydrogenbomb(p.x + p.w / 2 - 18 + p.facing * 12, p.y + 2, p.facing));
      Sfx.bombThrow();
    }
  }

  // ----- 召唤宇航员队友（仅最终 Boss 第二阶段）-----
  if (this.summonCd > 0) this.summonCd = Math.max(0, this.summonCd - dt);
  if (this.summonMsgT > 0) this.summonMsgT = Math.max(0, this.summonMsgT - dt);
  if (this.phaseBannerT > 0) this.phaseBannerT = Math.max(0, this.phaseBannerT - dt);
  if (Input.actionPressed('summon')) this._trySummon();

  // ----- 重力 -----
  p.vy += s.gravity * f;
  if (p.vy > G_MAX_FALL) p.vy = G_MAX_FALL;

  // ----- 水平移动 -----
  p.x += p.vx * f;
  if (p.x < 0) p.x = 0;
  if (p.x > s.width - p.w) p.x = s.width - p.w;

  // ----- 垂直移动 + 平台/地面碰撞 -----
  p.prevBottom = p.y + p.h;
  p.y += p.vy * f;
  p.onGround = false;
  // 地面
  if (p.y + p.h >= s.groundY) {
    p.y = s.groundY - p.h;
    if (p.vy > 0) {
      if (p.vy > 6) { Sfx.land(); this._dust(p.x + p.w / 2, s.groundY, 5); }
      p.vy = 0;
    }
    p.onGround = true;
  }
  // 单向平台（从下方穿过，落到顶部）
  for (var i = 0; i < this.platforms.length; i++) {
    var pl = this.platforms[i];
    if (p.vy >= 0 &&
        p.prevBottom <= pl.y + 3 &&
        p.y + p.h >= pl.y && p.y + p.h <= pl.y + pl.h + 24 &&
        p.x + p.w > pl.x + 6 && p.x < pl.x + pl.w - 6) {
      p.y = pl.y - p.h;
      p.vy = 0;
      p.onGround = true;
    }
  }

  // 掉出底部
  if (p.y > s.groundY + 360) { this.fellOff(); return; }
  } // end if (!p.grabbed)

  // ----- 相机 -----
  var targetCam = Util.clamp(p.x - VIEW.W * 0.375, 0, Math.max(0, s.width - VIEW.W));
  this.camera.x += (targetCam - this.camera.x) * Math.min(1, 0.12 * f);

  // ----- 实体更新 -----
  for (var j = 0; j < this.entities.length; j++) {
    this._updateEntity(this.entities[j], dt, f, s);
  }
  // 清理失效实体
  this.entities = this.entities.filter(function (e) {
    if (e.type === 'particle') return e.life > 0;
    if (e.type === 'crater') return e.life > 0;
    if (e.type === 'snowball') return e.alive;
    if (e.type === 'house') return e.alive;
    if (e.type === 'poopbeast') return e.alive || e.deadT < 0.4;
    if (e.type === 'snotbeast' || e.type === 'sockbeast') return e.alive || e.deadT < 0.4;
    if (e.type === 'hornbeast' || e.type === 'rollbeast' || e.type === 'snotworm' || e.type === 'littlesnake') return e.alive || e.deadT < 0.4;
    if (e.type === 'spiderboss' || e.type === 'timedevourer' || e.type === 'devilbeast' || e.type === 'crabbeast' || e.type === 'midspider' || e.type === 'spiderling' || e.type === 'gianttimedevourer' || e.type === 'emperorsnake' || e.type === 'threeheadsnake') return e.alive || e.fallT < 2.6;
    if (e.type === 'bullet' || e.type === 'fireball' || e.type === 'missile') return e.alive;
    if (e.type === 'devilfire') return e.alive;
    if (e.type === 'atombomb' || e.type === 'hydrogenbomb' || e.type === 'explosion') return e.alive;
    if (e.type === 'snotball' || e.type === 'slime' || e.type === 'stink') return e.alive;
    if (e.type === 'webball' || e.type === 'axe' || e.type === 'timeshock') return e.alive;
    if (e.type === 'ally') return e.alive || e.deadT < 0.6;
    return true;
  });

  // ----- 天上掉东西（雪球雨 + 房子雨）-----
  if (s.snowRate || s.houseDist) this._spawnHazards(dt, f, s);

  // ----- 第 4 幕：长角兽/滚球兽源源不断登场 -----
  if (s.needKills) this._spawnBeasts(dt, s);

  // ----- 第 4 幕：踩够 60 只长角兽 → 飞船从天上降落 -----
  if (s.needKills && !this._shipSpawned && this.killCount >= s.needKills) {
    this._shipSpawned = true;
    var sh = Entities.ship(s.ship.x, -120);
    sh.landing = true;
    sh.landed = false;
    sh.targetY = s.ship.y;
    this.entities.push(sh);
  }

  // ----- 碰撞 -----
  this._collisions(s);

  // ----- 目标达成 -----
  if (this.state === 'playing') this._checkGoal(s, dt);
};

Game.prototype._updateEntity = function (e, dt, f, s) {
  if (e.type === 'ally') { this._updateAlly(e, dt, f, s); return; }
  if (e.type === 'snowball') {
    if (e.mode === 'roll') {
      e.x += e.vx * f;
      e.spin += Math.abs(e.vx) * 0.06 * f;
      if (e.x + e.r * 2 < this.camera.x - 180) e.alive = false;
    } else { // fall
      e.y += e.vy * f;
      e.vy += 0.06 * f;
      e.spin += 0.1 * f;
      if (e.y + e.r * 2 >= s.groundY) {
        this.entities.push(Entities.crater(e.x + e.r, s.groundY + 9));
        this._dust(e.x + e.r, s.groundY, 8);
        this.shake = Math.max(this.shake, 6);
        e.alive = false;
      } else if (e.y > s.groundY + 360) e.alive = false;
    }
  } else if (e.type === 'house') {
    // 房子从天上砸下来：越落越快，落地砸出大坑
    e.wob += dt * 5;
    e.y += e.vy * f;
    e.vy += 0.06 * f;
    if (e.y + e.h >= s.groundY) {
      this.entities.push(Entities.crater(e.x + e.w / 2, s.groundY + 9));
      this._dust(e.x + e.w / 2, s.groundY, 12, '#c8b090');
      this.shake = Math.max(this.shake, 8);
      Sfx.houseCrash();
      e.alive = false;
    } else if (e.y > s.groundY + 360) e.alive = false;
  } else if (e.type === 'poopbeast') {
    if (e.alive) {
      e.x += e.vx * f;
      if (e.x < e.x1) { e.x = e.x1; e.vx = Math.abs(e.vx); }
      if (e.x + e.w > e.x2) { e.x = e.x2 - e.w; e.vx = -Math.abs(e.vx); }
      e.spin += 0.1 * f;
    } else {
      e.deadT += dt;
    }
  } else if (e.type === 'hornbeast') {
    if (e.alive) {
      // 慢悠悠朝玩家走（好让小朋友踩到头）
      var hp = this.player;
      e.dir = (hp.x + hp.w / 2 < e.x + e.w / 2) ? -1 : 1;
      e.x += e.dir * e.speed * f;
      if (e.x < 20) e.x = 20;
      if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
      e.anim += dt * 8;
    } else {
      e.deadT += dt;
    }
  } else if (e.type === 'rollbeast') {
    if (e.alive) {
      e.life -= dt;
      if (e.life <= 0) { e.alive = false; return; }
      e.x += e.vx * f;
      e.spin += Math.abs(e.vx) * 0.05 * f;
      if (e.x < 20) { e.x = 20; e.vx = Math.abs(e.vx); }
      if (e.x + e.w > s.width - 20) { e.x = s.width - 20 - e.w; e.vx = -Math.abs(e.vx); }
      if (e.x + e.w < this.camera.x - 260) e.alive = false;
    } else {
      e.deadT += dt;
    }
  } else if (e.type === 'snotworm') {
    if (e.alive) {
      e.anim += dt * 6;
      e.x += e.vx * f;
      if (e.x < e.x1) { e.x = e.x1; e.vx = Math.abs(e.vx); }
      if (e.x + e.w > e.x2) { e.x = e.x2 - e.w; e.vx = -Math.abs(e.vx); }
    } else {
      e.deadT += dt;
    }
  } else if (e.type === 'littlesnake') {
    if (e.alive) {
      e.anim += dt * 8;
      if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
      var lsp = this.player;
      e.dir = (lsp.x + lsp.w / 2) < (e.x + e.w / 2) ? -1 : 1;
      if (e.lunging > 0) {
        // 扑咬：短暂加速冲向玩家
        e.lunging -= dt;
        e.x += e.dir * (e.big ? 6.0 : 4.4) * f;
      } else {
        e.x += e.dir * e.speed * f;
        e.lungeT -= dt;
        if (e.lungeT <= 0) {
          var ldist = Math.abs(lsp.x - e.x);
          if (ldist < (e.big ? 520 : 420)) e.lunging = 0.5;
          e.lungeT = Util.rand(1.4, 3.0);
        }
      }
      if (e.x < e.x1) { e.x = e.x1; e.vx = Math.abs(e.vx); }
      if (e.x + e.w > e.x2) { e.x = e.x2 - e.w; e.vx = -Math.abs(e.vx); }
    } else {
      e.deadT += dt;
    }
  } else if (e.type === 'snotbeast') {
    if (e.alive) {
      e.breathe += dt * 4;
      e.x += e.vx * f;
      if (e.x < e.x1) { e.x = e.x1; e.vx = Math.abs(e.vx); }
      if (e.x > e.x2) { e.x = e.x2; e.vx = -Math.abs(e.vx); }
      var pp = this.player;
      e.facing = (pp.x + pp.w / 2 < e.x + e.w / 2) ? -1 : 1;
      e.spitT -= dt;
      if (e.spitT <= 0) {
        if (Math.abs(pp.x - e.x) < 1050) {
          this.entities.push(Entities.snotball(e.x + e.w / 2 - 12 + e.facing * 30, e.y + 6, e.facing));
          Sfx.snotSpit();
          e.spitT = 2.5;
        } else {
          e.spitT = 0.5;
        }
      }
    } else {
      e.deadT += dt;
    }
  } else if (e.type === 'snotball') {
    e.vy += 0.3 * f;
    e.x += e.vx * f;
    e.y += e.vy * f;
    e.spin += 0.15 * f;
    e.life -= dt;
    if (e.y + e.h >= s.groundY) {
      // 落地变成一摊黏液
      this.entities.push(Entities.slime(e.x + e.w / 2 - 45, s.groundY - 14, 4));
      this._dust(e.x + e.w / 2, s.groundY, 5, '#a8d84a');
      Sfx.squelch();
      e.alive = false;
    } else if (e.life <= 0 || e.x + e.w < this.camera.x - 300 || e.x > this.camera.x + VIEW.W + 300) {
      e.alive = false;
    }
  } else if (e.type === 'slime') {
    e.bubble += dt;
    e.life -= dt;
    if (e.life <= 0) e.alive = false;
  } else if (e.type === 'sockbeast') {
    if (e.alive) {
      e.anim += dt * 6;
      if (e.onGround) {
        e.idleT -= dt;
        if (e.idleT <= 0) {
          // 到边界就转身，然后蹦起来
          if (e.x <= e.x1 + 12) e.dir = 1;
          else if (e.x + e.w >= e.x2 - 12) e.dir = -1;
          e.vy = -10.8;
          e.vx = e.dir * 2.25;
          e.onGround = false;
        }
      } else {
        e.vy += s.gravity * f;
        e.x += e.vx * f;
        e.y += e.vy * f;
        if (e.x < e.x1) { e.x = e.x1; e.vx = Math.abs(e.vx); }
        if (e.x + e.w > e.x2) { e.x = e.x2 - e.w; e.vx = -Math.abs(e.vx); }
        if (e.vy > 0 && e.y + e.h >= s.groundY) {
          // 落地：放出一圈臭气
          e.y = s.groundY - e.h;
          e.vy = 0; e.vx = 0;
          e.onGround = true;
          e.idleT = 0.85;
          this.entities.push(Entities.stink(e.x + e.w / 2, s.groundY));
          Sfx.stinkPuff();
          this._dust(e.x + e.w / 2, s.groundY, 6, '#8ac85a');
        }
      }
    } else {
      e.deadT += dt;
    }
  } else if (e.type === 'stink') {
    e.t += dt;
    e.r = 12 + (e.maxR - 12) * Util.clamp(e.t / e.dur, 0, 1);
    if (e.t >= e.dur) e.alive = false;
  } else if (e.type === 'webball') {
    e.vy += 0.25 * f;
    e.x += e.vx * f;
    e.y += e.vy * f;
    e.spin += 0.12 * f;
    e.life -= dt;
    if (e.y + e.h >= s.groundY) {
      this._dust(e.x + e.r, s.groundY, 5, '#e8e8f0');
      e.alive = false;
    } else if (e.life <= 0) e.alive = false;
  } else if (e.type === 'axe') {
    e.vy += 0.35 * f;
    if (e.vy > 16) e.vy = 16;
    e.x += e.vx * f;
    e.y += e.vy * f;
    e.spin += 0.3 * f;
    e.life -= dt;
    if (e.y + e.h >= s.groundY) {
      this._dust(e.x + e.w / 2, s.groundY, 6, '#c8c8d0');
      e.alive = false;
    } else if (e.life <= 0 || e.x + e.w < this.camera.x - 300 || e.x > this.camera.x + VIEW.W + 300) {
      e.alive = false;
    }
  } else if (e.type === 'timeshock') {
    e.x += e.vx * f;
    e.life -= dt;
    if (e.life <= 0 || e.x + e.w < this.camera.x - 300 || e.x > this.camera.x + VIEW.W + 300) e.alive = false;
  } else if (e.type === 'spiderboss') {
    this._updateSpider(e, dt, f, s);
  } else if (e.type === 'midspider') {
    this._updateMidspider(e, dt, f, s);
  } else if (e.type === 'spiderling') {
    this._updateSpiderling(e, dt, f, s);
  } else if (e.type === 'timedevourer') {
    this._updateTimeDevourer(e, dt, f, s);
  } else if (e.type === 'gianttimedevourer') {
    this._updateTimeDevourer(e, dt, f, s);
  } else if (e.type === 'emperorsnake') {
    this._updateEmperorSnake(e, dt, f, s);
  } else if (e.type === 'threeheadsnake') {
    this._updateThreeHeadSnake(e, dt, f, s);
  } else if (e.type === 'snakebite') {
    e.x += e.vx * f; e.life -= dt;
    if (e.life <= 0 || e.x + e.w < 0 || e.x > s.width) e.alive = false;
  } else if (e.type === 'snakevenom') {
    e.vy += s.gravity * 0.5 * f; e.x += e.vx * f; e.y += e.vy * f; e.spin += 0.2 * f; e.life -= dt;
    if (e.y + e.h >= s.groundY && e.vy > 0) { e.y = s.groundY - e.h; e.vy = -3; }
    if (e.life <= 0 || e.x + e.w < 0 || e.x > s.width) e.alive = false;
  } else if (e.type === 'snakeconstrict') {
    e.t += dt; e.r = 20 + (e.maxR - 20) * Math.min(1, e.t / (e.dur * 0.5));
    if (e.t >= e.dur) e.alive = false;
  } else if (e.type === 'devilbeast') {
    this._updateDevil(e, dt, f, s);
  } else if (e.type === 'crabbeast') {
    this._updateCrab(e, dt, f, s);
  } else if (e.type === 'bullet') {
    // 快速平飞（几乎无重力），飞出屏幕或超出射程即消失
    e.x += e.vx * f;
    e.life -= dt;
    if (e.life <= 0 || e.x + e.w < 0 || e.x > s.width) e.alive = false;
  } else if (e.type === 'fireball') {
    // 带重力走抛物线，落地弹跳；飞行约 2.5s 或弹跳 3 次后消失
    e.vy += s.gravity * 0.55 * f;
    if (e.vy > 18) e.vy = 18;
    e.x += e.vx * f;
    e.y += e.vy * f;
    e.spin += 0.25 * f;
    e.life -= dt;
    if (e.y + e.h >= s.groundY && e.vy > 0) {
      e.y = s.groundY - e.h;
      e.vy = -7.5;
      e.bounces++;
      this._dust(e.x + e.r, s.groundY, 4, '#ff9a3a');
      if (e.bounces >= 3) { e.alive = false; this._dust(e.x + e.r, e.y + e.r, 8, '#ff7a2a'); }
    }
    // 落到单向平台上也会弹
    for (var pi = 0; pi < this.platforms.length; pi++) {
      var pf = this.platforms[pi];
      if (e.vy > 0 && e.y + e.h >= pf.y && e.y + e.h <= pf.y + pf.h + 14 &&
          e.x + e.w > pf.x + 4 && e.x < pf.x + pf.w - 4) {
        e.y = pf.y - e.h;
        e.vy = -7.5;
        e.bounces++;
        if (e.bounces >= 3) { e.alive = false; this._dust(e.x + e.r, e.y + e.r, 8, '#ff7a2a'); }
        break;
      }
    }
    if (e.life <= 0 || e.x + e.w < 0 || e.x > s.width) e.alive = false;
  } else if (e.type === 'devilfire') {
    // 魔鬼兽的火焰弹：水平平飞，飞出屏幕或寿命耗尽即消失
    e.x += e.vx * f;
    e.spin += 0.3 * f;
    e.life -= dt;
    if (e.life <= 0 || e.x + e.w < 0 || e.x > s.width) e.alive = false;
  } else if (e.type === 'missile') {
    // 又快又大、直飞穿屏，后面拖着小烟
    e.x += e.vx * f;
    e.life -= dt;
    e.puff += dt;
    if (e.puff > 0.05) {
      e.puff = 0;
      this.entities.push(Entities.particle(e.x + (e.vx > 0 ? 2 : e.w - 2), e.y + e.h / 2, {
        vx: -Util.sign(e.vx) * Util.rand(0.5, 1.5), vy: Util.rand(-0.5, 0.5),
        life: 0.35, color: '#c8ccd8', size: Util.randInt(3, 5), gravity: 0
      }));
    }
    if (e.life <= 0 || e.x + e.w < 0 || e.x > s.width) e.alive = false;
  } else if (e.type === 'atombomb' || e.type === 'hydrogenbomb') {
    // 抛出去：落地、超时或命中敌人就炸开大爆炸
    e.vy += s.gravity * 0.6 * f;
    if (e.vy > 18) e.vy = 18;
    e.x += e.vx * f;
    e.y += e.vy * f;
    e.spin += 0.2 * f;
    e.life -= dt;
    if (e.y + e.h >= s.groundY) {
      this._explode(e.x + e.w / 2, s.groundY - 10, e.boomR, e.boomDmg);
      e.alive = false;
    } else if (e.life <= 0) {
      this._explode(e.x + e.w / 2, e.y + e.h / 2, e.boomR, e.boomDmg);
      e.alive = false;
    } else if (e.x + e.w < 0 || e.x > s.width) {
      e.alive = false;
    }
  } else if (e.type === 'explosion') {
    // 冲击光环由小变大，约 0.5 秒消失（伤害在生成瞬间已结算）
    e.t += dt;
    e.r = 10 + (e.maxR - 10) * Util.clamp(e.t / e.dur, 0, 1);
    if (e.t >= e.dur) e.alive = false;
  } else if (e.type === 'flag') {
    e.wave += dt;
  } else if (e.type === 'castle') {
    e.glow += dt;
  } else if (e.type === 'ship') {
    e.bob += dt;
    if (e.landing) {
      e.y += 5.0 * f;
      if (e.y >= e.targetY) {
        e.y = e.targetY;
        e.landing = false;
        e.landed = true;
        this._shipLanded = true;
        this.shake = Math.max(this.shake, 7);
        this._dust(e.x + e.w / 2, s.groundY, 12, '#cfd8e8');
        Sfx.shipLand();
      }
    }
  } else if (e.type === 'particle') {
    e.x += e.vx * f;
    e.y += e.vy * f;
    e.vy += e.gravity * f;
    e.life -= dt;
  } else if (e.type === 'crater') {
    e.life -= dt;
  } else if (e.type === 'rocket') {
    if (e.flameT > 0) e.flameT = 1;
  }
};

// 大蜘蛛兽：在地上慢慢逼近玩家；每隔约 2.4s 吐一颗蛛丝球；
// 每隔约 5s 先抬身预警（画「!」），再朝玩家扑过来，落地砸出尘土
Game.prototype._updateSpider = function (e, dt, f, s) {
  if (!e.alive) { e.fallT += dt; return; }
  if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
  var p = this.player;
  var pcx = p.x + p.w / 2;
  var ecx = e.x + e.w / 2;
  if (e.pouncing) {
    e.vy += s.gravity * f;
    if (e.vy > 20) e.vy = 20;
    e.x += e.vx * f;
    e.y += e.vy * f;
    if (e.x < 20) { e.x = 20; e.vx = Math.abs(e.vx) * 0.5; }
    if (e.x + e.w > s.width - 20) { e.x = s.width - 20 - e.w; e.vx = -Math.abs(e.vx) * 0.5; }
    if (e.vy > 0 && e.y + e.h >= s.groundY) {
      e.y = s.groundY - e.h;
      e.vy = 0; e.vx = 0;
      e.pouncing = false;
      this.shake = Math.max(this.shake, 10);
      this._dust(ecx, s.groundY, 14, '#8a5a3a');
      Sfx.shockCast();
    }
  } else if (e.windupT > 0) {
    e.windupT -= dt;
    if (e.windupT <= 0) {
      e.pouncing = true;
      e.vy = -12.5;
      e.vx = Util.clamp((pcx - ecx) * 0.016, -6, 6);
    }
  } else {
    e.dir = pcx < ecx ? -1 : 1;
    e.x += e.dir * 1.05 * f;
    if (e.x < e.x1) e.x = e.x1;
    if (e.x > e.x2) e.x = e.x2;
    if (e.x < 20) e.x = 20;
    if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
    e.anim += dt * 6;
    // 吐蛛丝球
    e.spitT -= dt;
    if (e.spitT <= 0) {
      if (Math.abs(pcx - ecx) < 1100) {
        this.entities.push(Entities.webball(ecx - 13 + e.dir * 30, e.y + 40, e.dir));
        Sfx.webSpit();
        e.spitT = 2.4;
      } else {
        e.spitT = 0.5;
      }
    }
    // 扑击计时：玩家离得不太远才发动（不然白扑）
    e.pounceT -= dt;
    if (e.pounceT <= 0) {
      if (Math.abs(pcx - ecx) < 950) e.windupT = 0.55;
      e.pounceT = 5.2;
    }
    // 大蜘蛛兽专属：在玩家脚下布一张减速网（吐网陷阱），限制走位
    if (e.type === 'spiderboss') {
      e.snareT -= dt;
      if (e.snareT <= 0) {
        if (Math.abs(pcx - ecx) < 1100) {
          this.entities.push(Entities.slime(p.x + p.w / 2 - 45, s.groundY - 14, 4));
          Sfx.webSpit();
          e.snareT = 6.5;
        } else { e.snareT = 0.5; }
      }
    }
  }
};

// 终极蜘蛛怪（骷髅头）：独立 AI —— 三连蛛丝、扑击落地震波、召唤幼蛛
Game.prototype._updateMidspider = function (e, dt, f, s) {
  if (!e.alive) { e.fallT += dt; return; }
  if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
  var p = this.player;
  var pcx = p.x + p.w / 2;
  var ecx = e.x + e.w / 2;
  if (e.pouncing) {
    e.vy += s.gravity * f;
    if (e.vy > 20) e.vy = 20;
    e.x += e.vx * f;
    e.y += e.vy * f;
    if (e.x < 20) { e.x = 20; e.vx = Math.abs(e.vx) * 0.5; }
    if (e.x + e.w > s.width - 20) { e.x = s.width - 20 - e.w; e.vx = -Math.abs(e.vx) * 0.5; }
    if (e.vy > 0 && e.y + e.h >= s.groundY) {
      e.y = s.groundY - e.h;
      e.vy = 0; e.vx = 0;
      e.pouncing = false;
      this.shake = Math.max(this.shake, 12);
      this._dust(ecx, s.groundY, 16, '#cbb3c8');
      Sfx.shockCast();
      // 落地震波：贴地两道冲击波（区别于大蜘蛛兽的普通扑击）
      this.entities.push(Entities.timeshock(ecx, s.groundY, -1));
      this.entities.push(Entities.timeshock(ecx, s.groundY, 1));
    }
  } else if (e.windupT > 0) {
    e.windupT -= dt;
    if (e.windupT <= 0) {
      e.pouncing = true;
      e.vy = -13.5;
      e.vx = Util.clamp((pcx - ecx) * 0.016, -6, 6);
    }
  } else {
    e.dir = pcx < ecx ? -1 : 1;
    e.x += e.dir * 1.05 * f;
    if (e.x < e.x1) e.x = e.x1;
    if (e.x > e.x2) e.x = e.x2;
    if (e.x < 20) e.x = 20;
    if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
    e.anim += dt * 6;
    // 单发蛛丝
    e.spitT -= dt;
    if (e.spitT <= 0) {
      if (Math.abs(pcx - ecx) < 1100) {
        this.entities.push(Entities.webball(ecx - 13 + e.dir * 30, e.y + 40, e.dir));
        Sfx.webSpit();
        e.spitT = 2.6;
      } else { e.spitT = 0.5; }
    }
    // 三连蛛丝（扇形齐射）
    e.volleyT -= dt;
    if (e.volleyT <= 0) {
      if (Math.abs(pcx - ecx) < 1100) {
        for (var vi = -1; vi <= 1; vi++) {
          var wb = Entities.webball(ecx - 13 + e.dir * 30, e.y + 40, e.dir);
          wb.vx = e.dir * (2.8 + vi * 0.9);
          wb.vy = -5.5 + vi * 1.6;
          this.entities.push(wb);
        }
        Sfx.webSpit();
        e.volleyT = 4.2;
      } else { e.volleyT = 0.5; }
    }
    // 扑击（落地震波）
    e.pounceT -= dt;
    if (e.pounceT <= 0) {
      if (Math.abs(pcx - ecx) < 950) e.windupT = 0.55;
      e.pounceT = 5.6;
    }
    // 召唤幼蛛
    e.summonT -= dt;
    if (e.summonT <= 0) {
      for (var si = 0; si < 2; si++) {
        var sx = Util.clamp(ecx + (si === 0 ? -1 : 1) * 70, 40, s.width - 80);
        this.entities.push(Entities.spiderling(sx, s.groundY, e.dir));
      }
      Sfx.webSpit();
      this._dust(ecx, e.y + 60, 8, '#cbb3c8');
      e.summonT = 9.0;
    }
  }
};

// 幼蛛：贴地朝玩家爬；可踩扁/打掉，碰到扣 1 心
Game.prototype._updateSpiderling = function (e, dt, f, s) {
  if (!e.alive) { e.deadT += dt; return; }
  if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
  var p = this.player;
  e.dir = (p.x + p.w / 2) < (e.x + e.w / 2) ? -1 : 1;
  e.x += e.dir * e.speed * f;
  if (e.x < 20) e.x = 20;
  if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
  e.anim += dt * 6;
};

// 魔鬼兽：悬浮逼近；吐火焰弹、俯冲砸地，外加三向火环与火墙（水平扇射）
Game.prototype._updateDevil = function (e, dt, f, s) {
  if (!e.alive) { e.fallT += dt; return; }
  if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
  var p = this.player;
  var pcx = p.x + p.w / 2;
  var ecx = e.x + e.w / 2;
  e.anim += dt * 3;
  if (e.diving) {
    e.vy += s.gravity * f;
    if (e.vy > 20) e.vy = 20;
    e.x += e.vx * f;
    e.y += e.vy * f;
    if (e.x < 20) { e.x = 20; e.vx = Math.abs(e.vx) * 0.5; }
    if (e.x + e.w > s.width - 20) { e.x = s.width - 20 - e.w; e.vx = -Math.abs(e.vx) * 0.5; }
    if (e.vy > 0 && e.y + e.h >= s.groundY) {
      e.y = s.groundY - e.h;
      e.vy = 0; e.vx = 0;
      e.diving = false;
      this.shake = Math.max(this.shake, 10);
      this._dust(ecx, s.groundY, 14, '#a04020');
      Sfx.shockCast();
      e.fireT = 1.0;
    }
    return;
  }
  if (e.windupT > 0) {
    e.windupT -= dt;
    if (e.windupT <= 0) {
      e.diving = true;
      e.vy = -9;
      e.vx = Util.clamp((pcx - ecx) * 0.02, -7, 7);
    }
    return;
  }
  // 悬浮（上下浮动）
  e.y = e.baseY + Math.sin(e.anim) * 10;
  e.dir = pcx < ecx ? -1 : 1;
  e.x += e.dir * 0.95 * f;
  if (e.x < e.x1) e.x = e.x1;
  if (e.x > e.x2) e.x = e.x2;
  if (e.x < 20) e.x = 20;
  if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
  // 吐火焰弹
  e.fireT -= dt;
  if (e.fireT <= 0) {
    if (Math.abs(pcx - ecx) < 1100) {
      this.entities.push(Entities.devilfire(ecx - 13 + e.dir * 30, e.y + 60, e.dir));
      Sfx.webSpit();
      e.fireT = 1.8;
    } else { e.fireT = 0.5; }
  }
  // 俯冲计时
  e.diveT -= dt;
  if (e.diveT <= 0) {
    if (Math.abs(pcx - ecx) < 950) e.windupT = 0.5;
    e.diveT = 4.5;
  }
  // 三向火环（左、右、朝玩家各一发）
  e.ringT -= dt;
  if (e.ringT <= 0) {
    if (Math.abs(pcx - ecx) < 1100) {
      this.entities.push(Entities.devilfire(ecx - 13, e.y + 60, -1));
      this.entities.push(Entities.devilfire(ecx - 13, e.y + 60, 1));
      this.entities.push(Entities.devilfire(ecx - 13 + e.dir * 30, e.y + 60, e.dir));
      Sfx.webSpit();
      e.ringT = 5.5;
    } else { e.ringT = 0.5; }
  }
  // 火墙（朝玩家方向、不同高度三连，形成一道火墙）
  e.wallT -= dt;
  if (e.wallT <= 0) {
    if (Math.abs(pcx - ecx) < 1100) {
      for (var wi = 0; wi < 3; wi++) {
        this.entities.push(Entities.devilfire(ecx - 13 + e.dir * 30, e.y + 30 + wi * 30, e.dir));
      }
      Sfx.webSpit();
      e.wallT = 7.0;
    } else { e.wallT = 0.5; }
  }
};

// 大螃蟹兽：横向爬行逼近；巨钳砸地震波、泡泡扇、钳击横扫、缩壳地面冲撞
Game.prototype._updateCrab = function (e, dt, f, s) {
  if (!e.alive) { e.fallT += dt; return; }
  if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
  var p = this.player;
  var pcx = p.x + p.w / 2;
  var ecx = e.x + e.w / 2;

  // 缩壳冲撞：预警后高速横冲，玩家需跳起或让开
  if (e.charging > 0) {
    e.charging -= dt;
    e.x += e.chargeDir * 9.0 * f;
    if (e.x < 20) { e.x = 20; e.charging = 0; }
    if (e.x + e.w > s.width - 20) { e.x = s.width - 20 - e.w; e.charging = 0; }
    this._dust(e.x + (e.chargeDir > 0 ? e.w : 0), e.y + e.h - 16, 1, '#d98');
    return;
  }
  if (e.chargeWindup > 0) {
    e.chargeWindup -= dt;
    if (e.chargeWindup <= 0) { e.charging = 0.6; e.chargeDir = e.dir; }
    return;
  }

  e.anim += dt * 5;
  e.dir = pcx < ecx ? -1 : 1;
  e.x += e.dir * 0.85 * f;
  if (e.x < e.x1) e.x = e.x1;
  if (e.x > e.x2) e.x = e.x2;
  if (e.x < 20) e.x = 20;
  if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;

  // 巨钳砸地（贴地两道震荡波，朝两侧扩散，立刻发动）
  e.smashT -= dt;
  if (e.smashT <= 0) {
    if (Math.abs(pcx - ecx) < 1000) {
      this.entities.push(Entities.timeshock(ecx, s.groundY, -1));
      this.entities.push(Entities.timeshock(ecx, s.groundY, 1));
      Sfx.shockCast();
      this.shake = Math.max(this.shake, 8);
      e.smashT = 3.2;
    } else { e.smashT = 0.6; }
  }
  // 泡泡扇（三连，向上扇形）
  e.bubbleT -= dt;
  if (e.bubbleT <= 0) {
    if (Math.abs(pcx - ecx) < 1100) {
      for (var bi = -1; bi <= 1; bi++) {
        var bub = Entities.webball(ecx + e.dir * 40, e.y + 30, e.dir);
        bub.vx = e.dir * (2.4 + bi * 0.8);
        bub.vy = -7.5 + bi * 1.4;
        this.entities.push(bub);
      }
      Sfx.webSpit();
      e.bubbleT = 3.0;
    } else { e.bubbleT = 0.5; }
  }
  // 钳击横扫（单道快速冲击波，朝玩家方向）
  e.sweepT -= dt;
  if (e.sweepT <= 0) {
    if (Math.abs(pcx - ecx) < 1100) {
      this.entities.push(Entities.timeshock(ecx, s.groundY, e.dir));
      Sfx.shockCast();
      e.sweepT = 4.5;
    } else { e.sweepT = 0.6; }
  }
  // 缩壳冲撞（攒冷却后预警）
  e.chargeT -= dt;
  if (e.chargeT <= 0) {
    if (Math.abs(pcx - ecx) < 700) e.chargeWindup = 0.5;
    else e.chargeT = 0.6;
  }
};

// 光头强：慢慢逼近玩家；每隔约 2.6s 扔一把电锯；每隔约 5s 放出左右两道电锯气浪
// （贴地，跳起来就躲过）；每隔约 7s 一溜烟窜到玩家附近 —— 跑得比谁都快！
Game.prototype._updateTimeDevourer = function (e, dt, f, s) {
  if (!e.alive) { e.fallT += dt; return; }
  if (e.hurtT > 0) e.hurtT = Math.max(0, e.hurtT - dt);
  var p = this.player;
  var pcx = p.x + p.w / 2;
  var ecx = e.x + e.w / 2;

  // 变身中（进入第二阶段）：停手、闪光、冒蒸汽，不攻击
  if (e.transitionT > 0) {
    e.transitionT -= dt;
    e.steamT += dt;
    if (e.steamT > 0.12) {
      e.steamT = 0;
      this._dust(e.x + Util.rand(20, e.w - 20), e.y + 10, 1, '#ffd0a0');
    }
    this.shake = Math.max(this.shake, 5);
    return;
  }

  // 瞬移：先淡出消失，再出现在玩家附近
  if (e.blinkOut > 0) {
    e.blinkOut -= dt;
    if (e.blinkOut <= 0) {
      var side = Math.random() < 0.5 ? -1 : 1;
      e.x = Util.clamp(pcx + side * Util.rand(240, 380) - e.w / 2, e.x1, e.x2);
      if (e.x < 20) e.x = 20;
      if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
      e.blinkIn = 0.4;
      this._dust(e.x + e.w / 2, e.y + e.h / 2, 10, '#d9b06a');
      Sfx.timeBlink();
    }
    return;
  }
  if (e.blinkIn > 0) e.blinkIn -= dt;

  var phase2 = e.phase === 2;
  var speed = phase2 ? 1.95 : 0.95;
  e.dir = pcx < ecx ? -1 : 1;
  e.x += e.dir * speed * f;
  if (e.x < e.x1) e.x = e.x1;
  if (e.x > e.x2) e.x = e.x2;
  if (e.x < 20) e.x = 20;
  if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
  e.anim += dt * (phase2 ? 7 : 5);

  // 第二阶段冲撞：攒好冷却且离玩家不太远，就一头撞过去（跳起来可躲）
  if (phase2) {
    e.dashCd -= dt;
    if (e.dashing > 0) {
      e.dashing -= dt;
      e.x += e.dashDir * 7.0 * f;
      if (e.x < 20) e.x = 20;
      if (e.x + e.w > s.width - 20) e.x = s.width - 20 - e.w;
      this._dust(e.x + (e.dashDir > 0 ? e.w : 0), e.y + e.h - 16, 1, '#d9b06a');
    } else if (e.dashCd <= 0 && Math.abs(pcx - ecx) < 520 && e.blinkOut <= 0) {
      e.dashing = 0.5;
      e.dashDir = e.dir;
      Sfx.axeThrow();
    }
  }

  // 扔电锯
  e.axeT -= dt;
  if (e.axeT <= 0) {
    if (Math.abs(pcx - ecx) < 1050) {
      var lx = ecx - 17 + e.dir * 30, ly = e.y + 46;
      this.entities.push(Entities.axe(lx, ly, e.dir));
      if (phase2) {
        this.entities.push(Entities.axe(lx, ly - 26, e.dir));  // 第二阶段：高低错开双电锯
        e.axeT = 1.3;
      } else {
        e.axeT = 2.6;
      }
      Sfx.axeThrow();
    } else {
      e.axeT = 0.5;
    }
  }
  // 电锯气浪（贴地）
  e.shockT -= dt;
  if (e.shockT <= 0) {
    if (Math.abs(pcx - ecx) < 1500) {
      this.entities.push(Entities.timeshock(ecx, s.groundY, -1));
      this.entities.push(Entities.timeshock(ecx, s.groundY, 1));
      Sfx.shockCast();
      this.shake = Math.max(this.shake, phase2 ? 10 : 8);
      e.shockT = phase2 ? 2.8 : 5.2;
    } else {
      e.shockT = 0.6;
    }
  }
  // 瞬移计时（第二阶段更快）
  e.blinkT -= dt;
  if (e.blinkT <= 0) {
    e.blinkOut = 0.4;
    e.blinkT = phase2 ? 4.0 : 7.0;
    Sfx.timeBlink();
  }
};

// Boss 受击：扣血 + 闪白 + 音效；归零则死亡
Game.prototype._updateAlly = function (e, dt, f, s) {
  if (!e.alive) { e.deadT += dt; return; }
  if (e.invincible > 0) e.invincible = Math.max(0, e.invincible - dt);
  e.anim += dt * 10;
  var p = this.player;
  // 找光头强（普通版或巨化版）
  var boss = null;
  for (var i = 0; i < this.entities.length; i++) {
    var b = this.entities[i];
    if ((b.type === 'timedevourer' || b.type === 'gianttimedevourer' || b.type === 'emperorsnake' || b.type === 'threeheadsnake') && b.alive) { boss = b; break; }
  }
  // 跟随玩家，站在其侧后方（side 决定左右）
  var targetX = p.x + e.side * 78;
  var dx = targetX - e.x;
  var want = Util.clamp(dx, -3.2, 3.2);
  e.vx = Util.approach(e.vx, want, 0.5 * f);
  // 朝向：有 Boss 朝 Boss，否则朝移动方向
  e.facing = boss ? ((boss.x + boss.w / 2) < (e.x + e.w / 2) ? -1 : 1)
                  : (dx < 0 ? -1 : 1);
  // 重力 + 地面
  e.vy += s.gravity * f;
  if (e.vy > G_MAX_FALL) e.vy = G_MAX_FALL;
  e.x += e.vx * f;
  e.y += e.vy * f;
  if (e.y + e.h >= s.groundY) { e.y = s.groundY - e.h; e.vy = 0; e.onGround = true; }
  else e.onGround = false;
  if (e.x < 0) e.x = 0;
  if (e.x > s.width - e.w) e.x = s.width - e.w;
  // 开火：朝 Boss 射子弹（伤害小，但人多力量大）
  e.shootT -= dt;
  if (boss && e.shootT <= 0 && e.onGround && Math.abs(boss.x - e.x) < 1200) {
    var dir = (boss.x + boss.w / 2) < (e.x + e.w / 2) ? -1 : 1;
    var bx = dir > 0 ? e.x + e.w - 2 : e.x - 18;
    this.entities.push(Entities.bullet(bx, e.y + 22, dir));
    Sfx.allyShoot();
    e.shootT = Util.rand(0.8, 1.4);
  }
};

Game.prototype._hitAlly = function (al) {
  if (al.invincible > 0 || !al.alive) return;
  al.hearts--;
  al.invincible = 1.1;
  al.vx = -al.facing * 4;
  this._dust(al.x + al.w / 2, al.y + al.h / 2, 6, al.trim);
  Sfx.hurt();
  if (al.hearts <= 0) {
    al.alive = false;
    al.deadT = 0;
    this._dust(al.x + al.w / 2, al.y + al.h / 2, 14, al.suit);
    Sfx.bossHit();
  }
};

Game.prototype._getBoss = function () {
  for (var i = 0; i < this.entities.length; i++) {
    var e = this.entities[i];
    if ((e.type === 'spiderboss' || e.type === 'timedevourer' || e.type === 'devilbeast' || e.type === 'crabbeast' || e.type === 'midspider' || e.type === 'gianttimedevourer' || e.type === 'emperorsnake' || e.type === 'threeheadsnake') && e.alive) return e;
  }
  return null;
};

Game.prototype._countAllies = function () {
  var n = 0;
  for (var i = 0; i < this.entities.length; i++) {
    if (this.entities[i].type === 'ally' && this.entities[i].alive) n++;
  }
  return n;
};

Game.prototype._setSummonMsg = function (msg) {
  this.summonMsg = msg;
  this.summonMsgT = 2.2;
};

Game.prototype._trySummon = function () {
  var boss = this._getBoss();
  if (!boss || (boss.type !== 'timedevourer' && boss.type !== 'gianttimedevourer')) {
    this._setSummonMsg('召唤队友只在最终决战里能用哦');
    return;
  }
  if (boss.phase === 1) {
    this._setSummonMsg('先把光头强打到生气（血量过半）才能召唤队友！');
    return;
  }
  if (this._countAllies() >= MAX_ALLIES) {
    this._setSummonMsg('队友已经满员啦（' + MAX_ALLIES + ' 人）！');
    return;
  }
  if (this.summonCd > 0) return;   // 冷却中静默忽略
  this._spawnAlly(this._countAllies());
  this.summonCd = SUMMON_CD;
  Sfx.summon();
};

Game.prototype._spawnAlly = function (idx) {
  var def = ALLY_DEFS[idx % ALLY_DEFS.length];
  var side = (idx % 2 === 0) ? 1 : -1;
  var x = this.player.x + side * 90;
  var e = Entities.ally(x, this.player.y, def, side);
  this.entities.push(e);
  this._dust(x + e.w / 2, this.player.y + e.h, 8, def.trim);
};

Game.prototype._damageBoss = function (e, dmg) {
  if (!e.alive) return;
  e.hp -= dmg;
  this.bossHp[this.stageIndex] = e.hp;   // 记住残血：死亡重来接着打
  e.hurtT = 0.12;
  this.score += 50;
  Sfx.bossHit();
  this._dust(e.x + e.w / 2, e.y + e.h / 2, 5, '#c05a8a');
  // Boss 血量过半 → 进入第二阶段（暴怒），攻击频率翻倍
  if ((e.type === 'timedevourer' || e.type === 'gianttimedevourer' || e.type === 'emperorsnake' || e.type === 'threeheadsnake') && e.phase === 1 && e.hp <= e.maxHp * BOSS_PHASE2_FRAC) {
    e.phase = 2;
    e.transitionT = 1.2;
    e.biteT = 1.0; e.constrictT = 2.5; e.tailT = 3.5;
    if (e.type === 'threeheadsnake') { e.venomT = 1.6; e.mambaT = 2.0; }
    this.phaseBannerT = 2.4;
    this.phaseBannerMsg = (e.type === 'emperorsnake') ? '帝王蛇怪发怒了！'
      : (e.type === 'threeheadsnake') ? '三头帝王蛇·终极暴怒！'
      : '光头强生气了！';
    this.shake = Math.max(this.shake, 10);
    Sfx.angry();
  }
  if (e.hp <= 0) {
    e.hp = 0;
    this.bossHp[this.stageIndex] = 0;
    this._bossDie(e);
  }
};

Game.prototype._bossDie = function (e) {
  e.alive = false;
  e.fallT = 0;
  e.vy = 0;
  e.vx = 0;
  e.pouncing = false;
  e.windupT = 0;
  e.blinkOut = 0;
  e.blinkIn = 0;
  e.grabbing = false;   // 若正缠着玩家，立刻放开
  if (this.player && this.player.grabbed) {
    this.player.grabbed = false;
    this.player.invincible = 1.6;
  }
  this.score += 1000;
  this.shake = Math.max(this.shake, 12);
  this.bossClearT = 2.0;      // 胜利小节：放完「打败了 xx！」再进下一幕
  this.bossClearName = e.type === 'spiderboss' ? '大蜘蛛兽'
    : e.type === 'devilbeast' ? '魔鬼兽'
    : e.type === 'crabbeast' ? '大螃蟹兽'
    : e.type === 'midspider' ? '终极蜘蛛怪'
    : e.type === 'emperorsnake' ? '帝王蛇怪'
    : e.type === 'threeheadsnake' ? '三头帝王蛇'
    : '光头强';
  Sfx.bossDie();
};

// ===== 蛇怪通用：来回跑动巡逻（不再停在玩家身边）=====
Game.prototype._snakePatrol = function (e, dt, f, s, p, spd) {
  if (e.biting || e.constricting || e.grabbing) {
    // 出招 / 抓取时减速但仍保持惯性，不会完全僵住
    e.vx *= 0.85;
  } else {
    e.wanderT -= dt;
    if (e.wanderT <= 0) {
      // 多数时候朝玩家，偶尔反向 → 看起来在场地里来回跑动
      var toP = (p.x + p.w / 2) < (e.x + e.w / 2) ? -1 : 1;
      e.wanderDir = (Math.random() < 0.6) ? toP : (e.wanderDir >= 0 ? -1 : 1);
      e.wanderT = Util.rand(1.0, 2.2);
    }
    e.vx = e.wanderDir * spd;
    e.dir = e.wanderDir;
  }
  e.x += e.vx * f;
  if (e.x < e.x1) { e.x = e.x1; e.wanderDir = 1; e.vx = spd; }
  if (e.x + e.w > e.x2) { e.x = e.x2 - e.w; e.wanderDir = -1; e.vx = -spd; }
};

// ===== 蛇怪通用：来回跑动时撞到玩家 → 缠绕卷住（卷死）=====
Game.prototype._snakeGrab = function (e, dt, f, s, p) {
  // 安全兜底：Boss 死了但玩家还被缠着 → 立刻放开
  if (!e.alive && p.grabbed) {
    p.grabbed = false; p.invincible = 1.6;
    return;
  }
  if (!e.grabbing && !p.grabbed && p.invincible <= 0) {
    var sbx = e.x + 14, sby = e.y + 10, sbw = e.w - 28, sbh = e.h - 16;
    if (Util.aabb(p.x, p.y, p.w, p.h, sbx, sby, sbw, sbh)) {
      e.grabbing = true; e.grabT = 0; e.grabSqueeze = 0;
      p.grabbed = true; p.vx = 0; p.vy = 0;
      p.facing = e.dir >= 0 ? -1 : 1;
      this.shake = Math.max(this.shake, 9);
      Sfx.stomp();
    }
  }
  if (e.grabbing) {
    // 把玩家拖到蛇身底部（被缠住卷着一起走）
    p.x = e.x + e.w / 2 - p.w / 2;
    p.y = s.groundY - p.h;
    p.vx = 0; p.vy = 0;
    p.facing = e.dir >= 0 ? -1 : 1;
    e.grabT += dt;
    // 挤压两次：0.5s 与 1.1s 各扣 1 心（无视无敌帧，这是被「卷死」）
    if (e.grabSqueeze < 2) {
      var squeezeAt = e.grabSqueeze === 0 ? 0.5 : 1.1;
      if (e.grabT >= squeezeAt) {
        e.grabSqueeze++;
        this._crushPlayer(1);
        this.shake = Math.max(this.shake, 10);
        this._dust(p.x + p.w / 2, p.y + p.h / 2, 10, '#9ad04a');
      }
    }
    // 1.7s 后放开，把玩家弹开并给予短暂无敌
    if (e.grabT >= 1.7) {
      e.grabbing = false;
      p.grabbed = false;
      p.invincible = 1.6;
      p.vy = -11; p.vx = -e.dir * 5;
      e.wanderT = 0.5;
    }
  }
};

// 被蛇怪「卷死」缠绕：无视常规无敌帧、可一次扣多心的挤压伤害
Game.prototype._crushPlayer = function (hearts) {
  var p = this.player;
  if (!p || !p.alive) return;
  p.hearts -= hearts;
  Sfx.hurt();
  this._dust(p.x + p.w / 2, p.y + p.h / 2, 10, '#ff8a8a');
  if (p.hearts <= 0) {
    p.hearts = 0; p.alive = false; p.grabbed = false;
    this.state = 'gameover';
    Sfx.gameover();
  }
};

// ===== 帝王蛇怪 AI =====
Game.prototype._updateEmperorSnake = function (e, dt, f, s) {
  if (!e.alive) {
    e.fallT += dt;
    return;
  }
  e.anim += dt * 1.2;
  if (e.hurtT > 0) e.hurtT -= dt;
  if (e.transitionT > 0) { e.transitionT -= dt; return; }

  var p = this.player;
  // 来回跑动（之前是半固定、几乎不动，玩家躲旁边就打不到）
  var spd = e.phase === 2 ? 3.0 : 2.0;
  this._snakePatrol(e, dt, f, s, p, spd);

  // 咬击
  e.biteT -= dt;
  if (e.biteT <= 0 && !e.biting && !e.constricting && !e.grabbing) {
    e.biting = true;
    e.windupT = 0.5;
  }
  if (e.biting) {
    e.windupT -= dt;
    if (e.windupT <= 0) {
      // 发射咬击
      var bx = e.dir > 0 ? e.x + e.w - 20 : e.x + 20;
      this.entities.push(Entities.snakebite(bx, e.y + 60, e.dir));
      Sfx.shoot();
      e.biting = false;
      e.biteT = e.phase === 2 ? 1.5 : 2.8;
    }
  }

  // 缠绕（范围圈，仍是次要招式，主要威胁改为「接触卷死」）
  e.constrictT -= dt;
  if (e.constrictT <= 0 && !e.biting && !e.constricting && !e.grabbing) {
    e.constricting = true;
    e.windupT = 0.7;
  }
  if (e.constricting) {
    e.windupT -= dt;
    if (e.windupT <= 0) {
      this.entities.push(Entities.snakeconstrict(e.x + e.w / 2, s.groundY));
      this.shake = Math.max(this.shake, 6);
      e.constricting = false;
      e.constrictT = e.phase === 2 ? 3.5 : 6.0;
    }
  }

  // 接触缠绕：来回跑动撞到玩家 → 缠住卷死（替换原先「发个正弦波就结束」的无效盘绕）
  this._snakeGrab(e, dt, f, s, p);
};

// ===== 三头帝王蛇 AI =====
Game.prototype._updateThreeHeadSnake = function (e, dt, f, s) {
  if (!e.alive) {
    e.fallT += dt;
    return;
  }
  e.anim += dt * 1.5;
  if (e.hurtT > 0) e.hurtT -= dt;
  if (e.transitionT > 0) { e.transitionT -= dt; return; }

  // 自动召唤盟友（光头强、童童、飞飞）
  if (!e.alliesSummoned) {
    e.alliesSummoned = true;
    var allyDefs = [
      { name: '光头强', suit: '#3f7a34', trim: '#e8d8b0', allyType: 'guangtouqiang' },
      { name: '飞飞', suit: '#3a6fd9', trim: '#aadcff' },
      { name: '童童', suit: '#2fae6a', trim: '#bff0d0' }
    ];
    for (var ai = 0; ai < allyDefs.length; ai++) {
      var al = Entities.ally(this.player.x - 60 - ai * 45, s.spawn.y, allyDefs[ai], -1);
      al.facing = 1;
      this.entities.push(al);
    }
    this.phaseBannerT = 3.0;
    this.phaseBannerMsg = '盟友出场！光头强、飞飞、童童一起打三头帝王蛇！';
    this.shake = Math.max(this.shake, 8);
  }

  var p = this.player;
  // 来回跑动（之前几乎是半固定的，玩家躲旁边就打不到）
  var spd = e.phase === 2 ? 2.4 : 1.6;
  this._snakePatrol(e, dt, f, s, p, spd);

  // 帝王蛇头(0)：咬击
  if (e.headAlive[0]) {
    e.biteT -= dt;
    if (e.biteT <= 0 && !e.biting) {
      e.biting = true; e.windupT = 0.4;
    }
    if (e.biting) {
      e.windupT -= dt;
      if (e.windupT <= 0) {
        var bx = e.dir > 0 ? e.x + e.w - 20 : e.x + 20;
        this.entities.push(Entities.snakebite(bx, e.y + 100, e.dir));
        Sfx.shoot();
        e.biting = false;
        e.biteT = e.phase === 2 ? 1.8 : 3.0;
      }
    }
  }

  // 眼镜王蛇头(1)：毒液弹
  if (e.headAlive[1]) {
    e.venomT -= dt;
    if (e.venomT <= 0) {
      var vx = e.dir > 0 ? e.x + e.w - 30 : e.x + 30;
      this.entities.push(Entities.snakevenom(vx, e.y + 80, e.dir));
      Sfx.shoot();
      e.venomT = e.phase === 2 ? 2.0 : 3.5;
    }
  }

  // 黑曼巴头(2)：快速连咬
  if (e.headAlive[2]) {
    e.mambaT -= dt;
    if (e.mambaT <= 0) {
      e.mambaBurst = 3; // 连续 3 发
      e.mambaT = e.phase === 2 ? 3.0 : 5.0;
    }
    if (e.mambaBurst > 0) {
      e.windupT -= dt;
      if (e.windupT <= 0) {
        var mx = e.dir > 0 ? e.x + e.w - 20 : e.x + 20;
        this.entities.push(Entities.snakebite(mx, e.y + 140, e.dir));
        Sfx.shoot();
        e.mambaBurst--;
        e.windupT = 0.25;
      }
    }
  }

  // 缠绕
  e.constrictT -= dt;
  if (e.constrictT <= 0) {
    this.entities.push(Entities.snakeconstrict(e.x + e.w / 2, s.groundY));
    this.shake = Math.max(this.shake, 8);
    e.constrictT = e.phase === 2 ? 5.0 : 8.0;
  }

  // 接触缠绕：来回跑动撞到玩家 → 缠住卷死
  this._snakeGrab(e, dt, f, s, p);
};

// 投射物消灭小怪：复用踩头的死亡动画与分值
Game.prototype._killEnemy = function (e, score, color) {
  if (!e.alive) return;
  e.alive = false;
  e.deadT = 0;
  if (e.type === 'hornbeast') this.killCount++;   // 长角兽怎么死都计数
  this.score += score;
  Sfx.stomp();
  this._dust(e.x + e.w / 2, e.y + e.h / 2, 8, color);
};

// 原子弹/氢弹命中敌人：立刻炸开
Game.prototype._explodeBomb = function (pr) {
  if (!pr.alive) return;
  pr.alive = false;
  this._explode(pr.x + pr.w / 2, pr.y + pr.h / 2, pr.boomR, pr.boomDmg);
};

// 大爆炸：生成 'explosion' 冲击光环，并对范围内所有敌人/Boss 结算一次 AoE 伤害
Game.prototype._explode = function (cx, cy, r, dmg) {
  this.entities.push(Entities.explosion(cx, cy, r));
  this.shake = Math.max(this.shake, r / 22);
  Sfx.explosion(r > 200);
  this._dust(cx, cy, 14, '#ffb040');
  for (var j = 0; j < this.entities.length; j++) {
    var e = this.entities[j];
    if (!e.alive) continue;
    var ex = e.x + (e.w || 0) / 2, ey = e.y + (e.h || 0) / 2;
    if (Util.dist2(cx, cy, ex, ey) > r * r) continue;
    if (SHOOTABLE[e.type]) {
      this._killEnemy(e, SHOOTABLE[e.type][0], SHOOTABLE[e.type][1]);
    } else if (e.type === 'webball' || e.type === 'axe') {
      e.alive = false;
      this.score += 25;
      this._dust(ex, ey, 6, '#e8e8f0');
    } else if (e.type === 'spiderboss' || e.type === 'timedevourer' || e.type === 'devilbeast' || e.type === 'crabbeast' || e.type === 'midspider' || e.type === 'gianttimedevourer' || e.type === 'emperorsnake' || e.type === 'threeheadsnake') {
      this._damageBoss(e, dmg);
    }
  }
};

// 玩家的五种武器 → 敌人（不会伤到玩家自己）
Game.prototype._projectileHits = function (s) {
  for (var i = 0; i < this.entities.length; i++) {
    var pr = this.entities[i];
    if (!pr.alive) continue;
    var isBomb = pr.type === 'atombomb' || pr.type === 'hydrogenbomb';
    var dmg = WEAPON_DMG[pr.type];
    if (!dmg && !isBomb) continue;
    var px = pr.x, py = pr.y, pw = pr.w, ph = pr.h;
    for (var j = 0; j < this.entities.length; j++) {
      var e = this.entities[j];
      if (!e.alive || e === pr) continue;
      if (SHOOTABLE[e.type]) {
        // 命中盒比视觉略小一点（对小朋友友好）
        if (Util.aabb(px, py, pw, ph, e.x + 4, e.y + 4, e.w - 8, e.h - 6)) {
          if (e.type === 'littlesnake') {
            // 小蛇：普通一击死；蛇将（big）需多下命中
            if (isBomb) {
              this._explodeBomb(pr);
            } else {
              e.hp -= (WEAPON_DMG[pr.type] || 1);
              e.hurtT = 0.12;
              pr.alive = false;
              this._dust(e.x + e.w / 2, e.y + e.h / 2, 6, '#9ad04a');
              if (e.hp <= 0) {
                e.alive = false; e.deadT = 0;
                this.score += SHOOTABLE.littlesnake[0];
                Sfx.stomp();
                this._dust(e.x + e.w / 2, e.y + e.h / 2, 10, '#9ad04a');
              }
              if (pr.type !== 'bullet') this._dust(px + pw / 2, py + ph / 2, 10, '#ff9a3a');
            }
          } else if (isBomb) {
            this._explodeBomb(pr);
          } else {
            this._killEnemy(e, SHOOTABLE[e.type][0], SHOOTABLE[e.type][1]);
            pr.alive = false;
            if (pr.type !== 'bullet') this._dust(px + pw / 2, py + ph / 2, 10, '#ff9a3a');
          }
          break;
        }
      } else if (e.type === 'webball' || e.type === 'axe') {
        // Boss 扔出来的东西也能被打掉
        if (Util.aabb(px, py, pw, ph, e.x, e.y, e.w, e.h)) {
          if (isBomb) this._explodeBomb(pr);
          else {
            e.alive = false;
            this.score += 25;
            this._dust(e.x + e.w / 2, e.y + e.h / 2, 6, e.type === 'axe' ? '#c8c8d0' : '#e8e8f0');
            pr.alive = false;
          }
          break;
        }
      } else if (e.type === 'spiderboss' || e.type === 'timedevourer' || e.type === 'devilbeast' || e.type === 'crabbeast' || e.type === 'midspider' || e.type === 'gianttimedevourer' || e.type === 'emperorsnake' || e.type === 'threeheadsnake') {
        if (Util.aabb(px, py, pw, ph, e.x + 14, e.y + 10, e.w - 28, e.h - 18)) {
          if (isBomb) this._explodeBomb(pr);
          else {
            this._damageBoss(e, dmg);
            pr.alive = false;
            if (pr.type !== 'bullet') this._dust(px + pw / 2, py + ph / 2, 10, '#ffb060');
          }
          break;
        }
      }
    }
  }
};

// 天上掉东西：雪球雨（滚的 + 落的）+ 房子雨
Game.prototype._spawnHazards = function (dt, f, s) {
  var p = this.player;
  if (p.x < 150) return; // 起步保护
  var rate = s.snowRate;
  var i;
  if (rate) {
    var rollCount = 0;
    for (i = 0; i < this.entities.length; i++) {
      if (this.entities[i].type === 'snowball' && this.entities[i].mode === 'roll') rollCount++;
    }
    this.snowRollAcc += Math.max(0, p.vx) * f;
    if (this.snowRollAcc >= rate.rollDist && rollCount < (rate.max || 6)) {
      this.snowRollAcc = 0;
      var r = Util.randInt(27, 45);
      var sx = Math.min(p.x + 1140, s.width + 60);
      this.entities.push(Entities.snowball(sx, s.groundY - r * 2, 'roll', r));
    }
    this.snowFallAcc += Math.max(0, p.vx) * f;
    if (this.snowFallAcc >= rate.fallDist) {
      this.snowFallAcc = 0;
      var fx = p.x + Util.rand(-120, 480);
      this.entities.push(Entities.snowball(fx, -60, 'fall', Util.randInt(24, 36)));
    }
  }
  if (s.houseDist) {
    var houseCount = 0;
    for (i = 0; i < this.entities.length; i++) {
      if (this.entities[i].type === 'house' && this.entities[i].alive) houseCount++;
    }
    this.houseAcc += Math.max(0, p.vx) * f;
    if (this.houseAcc >= s.houseDist && houseCount < 3) {
      this.houseAcc = 0;
      this.entities.push(Entities.house(p.x + Util.rand(150, 540), -100));
    }
  }
};

// 第 4 幕：长角兽（每 hornEvery 秒 1~2 只，场上最多 6 只）+
// 滚球兽（每 rollEvery 秒 1 只，场上最多 2 只）源源不断地来
Game.prototype._spawnBeasts = function (dt, s) {
  var p = this.player;
  var i, e, hornCount = 0, rollCount = 0;
  for (i = 0; i < this.entities.length; i++) {
    e = this.entities[i];
    if (e.type === 'hornbeast' && e.alive) hornCount++;
    else if (e.type === 'rollbeast' && e.alive) rollCount++;
  }
  this.hornT -= dt;
  if (this.hornT <= 0) {
    this.hornT = s.hornEvery || 1.5;
    if (hornCount < 6) {
      var n = Util.randInt(1, 2);
      var sx = p.x + Util.rand(420, 720);
      if (sx > s.width - 80) sx = Math.max(60, p.x - Util.rand(420, 720));
      for (i = 0; i < n && hornCount < 6; i++) {
        var hx = Util.clamp(sx + i * Util.rand(60, 110), 60, s.width - 80);
        this.entities.push(Entities.hornbeast(hx, s.groundY));
        hornCount++;
      }
    }
  }
  this.rollT -= dt;
  if (this.rollT <= 0) {
    this.rollT = s.rollEvery || 7;
    if (rollCount < 2) {
      var dir = (p.x + 700 < s.width - 80) ? -1 : 1;
      var rx = dir < 0 ? Math.min(p.x + Util.rand(700, 1000), s.width - 80)
                       : Math.max(60, p.x - Util.rand(700, 1000));
      this.entities.push(Entities.rollbeast(rx, s.groundY, dir));
    }
  }
};

// 踩头判定：玩家正在下落，且上一帧脚底在兽头上方
Game.prototype._isStomp = function (e) {
  var p = this.player;
  return p.vy > 1 && p.prevBottom <= e.y + 15 &&
         p.y + p.h >= e.y && p.y + p.h <= e.y + 33 &&
         p.x + p.w > e.x + 6 && p.x < e.x + e.w - 6;
};

Game.prototype._doStomp = function (e, score, color) {
  e.alive = false;
  e.deadT = 0;
  this.score += score;
  var p = this.player;
  p.vy = -13.5;
  p.jumpCut = false;
  Sfx.stomp();
  this._dust(e.x + e.w / 2, e.y + e.h, 10, color);
};

// 踩扁长角兽：killCount+1；附近的长角兽会被一起震扁（连带，每只都计数）
Game.prototype._stompHorn = function (e) {
  this._doStomp(e, 100, '#e07830');
  this.killCount++;
  var cx = e.x + e.w / 2, cy = e.y + e.h / 2;
  for (var i = 0; i < this.entities.length; i++) {
    var o = this.entities[i];
    if (o !== e && o.type === 'hornbeast' && o.alive) {
      if (Util.dist2(cx, cy, o.x + o.w / 2, o.y + o.h / 2) < 130 * 130) {
        o.alive = false;
        o.deadT = 0;
        this.killCount++;
        this.score += 100;
        this._dust(o.x + o.w / 2, o.y + o.h / 2, 8, '#e07830');
      }
    }
  }
};

Game.prototype._collisions = function (s) {
  var p = this.player;
  // 玩家命中盒略小于视觉（对小朋友友好）
  var px = p.x + 7.5, py = p.y + 6, pw = p.w - 15, ph = p.h - 9;
  var pcx = p.x + p.w / 2, pcy = p.y + p.h / 2;
  for (var i = 0; i < this.entities.length; i++) {
    var e = this.entities[i];
    if (e.type === 'snowball' && e.alive) {
      var ex = e.x + 6, ey = e.y + 6, ew = e.w - 12, eh = e.h - 12;
      if (Util.aabb(px, py, pw, ph, ex, ey, ew, eh)) this.hitPlayer();
    } else if (e.type === 'house' && e.alive) {
      if (Util.aabb(px, py, pw, ph, e.x + 10, e.y + 8, e.w - 20, e.h - 12)) this.hitPlayer();
    } else if (e.type === 'poopbeast' && e.alive) {
      if (this._isStomp(e)) {
        this._doStomp(e, 100, '#7a4a22');
      } else if (Util.aabb(px, py, pw, ph, e.x + 6, e.y + 6, e.w - 12, e.h - 9)) {
        this.hitPlayer();
      }
    } else if (e.type === 'hornbeast' && e.alive) {
      if (this._isStomp(e)) {
        this._stompHorn(e);
      } else if (Util.aabb(px, py, pw, ph, e.x + 6, e.y + 6, e.w - 12, e.h - 9)) {
        this.hitPlayer();
      }
    } else if (e.type === 'rollbeast' && e.alive) {
      if (this._isStomp(e)) {
        this._doStomp(e, 150, '#3aa8a0');
      } else if (Util.aabb(px, py, pw, ph, e.x + 8, e.y + 8, e.w - 16, e.h - 12)) {
        this.hitPlayer();
      }
    } else if (e.type === 'snotworm' && e.alive) {
      if (this._isStomp(e)) {
        this._doStomp(e, 50, '#b8d84a');
      } else if (Util.aabb(px, py, pw, ph, e.x + 4, e.y + 4, e.w - 8, e.h - 6)) {
        this.hitPlayer();
      }
    } else if (e.type === 'littlesnake' && e.alive) {
      if (this._isStomp(e)) {
        if (e.big && e.hp > 1) {
          // 蛇将：踩头只削一层，弹起但不死
          e.hp--; e.hurtT = 0.12;
          var lp = this.player; lp.vy = -13.5; lp.jumpCut = false;
          Sfx.stomp(); this._dust(e.x + e.w / 2, e.y + e.h, 8, '#9ad04a');
        } else {
          this._doStomp(e, SHOOTABLE.littlesnake[0], '#9ad04a');
        }
      } else if (Util.aabb(px, py, pw, ph, e.x + 4, e.y + 4, e.w - 8, e.h - 6)) {
        this.hitPlayer();
      }
    } else if (e.type === 'snotbeast' && e.alive) {
      if (this._isStomp(e)) {
        this._doStomp(e, 150, '#a8c84a');
      } else if (Util.aabb(px, py, pw, ph, e.x + 7, e.y + 6, e.w - 14, e.h - 9)) {
        this.hitPlayer();
      }
    } else if (e.type === 'sockbeast' && e.alive) {
      if (this._isStomp(e)) {
        this._doStomp(e, 150, '#7a8aaa');
      } else if (Util.aabb(px, py, pw, ph, e.x + 6, e.y + 6, e.w - 12, e.h - 9)) {
        this.hitPlayer();
      }
    } else if (e.type === 'spiderling' && e.alive) {
      if (this._isStomp(e)) {
        this._doStomp(e, 50, '#cbb3c8');
      } else if (Util.aabb(px, py, pw, ph, e.x + 4, e.y + 4, e.w - 8, e.h - 6)) {
        this.hitPlayer();
      }
    } else if (e.type === 'snotball' && e.alive) {
      if (Util.aabb(px, py, pw, ph, e.x + 3, e.y + 3, e.w - 6, e.h - 6)) {
        e.alive = false;
        this._dust(e.x + e.r, e.y + e.r, 6, '#a8d84a');
        this.hitPlayer();
      }
    } else if (e.type === 'slime' && e.alive) {
      // 黏液不扣心，只会让人变慢
      if (p.slowT <= 0 && Util.aabb(px, py, pw, ph, e.x + 4, e.y, e.w - 8, e.h)) {
        p.slowT = 1.5;
        Sfx.squelch();
      }
    } else if (e.type === 'stink' && e.alive) {
      // 臭气不扣心，只会让人晕（左右反向）
      if (!e.applied && Util.dist2(pcx, pcy, e.x, e.y) < e.r * e.r) {
        e.applied = true;
        p.dizzyT = 1.2;
        Sfx.dizzy();
      }
    } else if (e.type === 'webball' && e.alive) {
      if (Util.aabb(px, py, pw, ph, e.x + 3, e.y + 3, e.w - 6, e.h - 6)) {
        e.alive = false;
        this._dust(e.x + e.r, e.y + e.r, 6, '#e8e8f0');
        this.hitPlayer();
      }
    } else if (e.type === 'axe' && e.alive) {
      if (Util.aabb(px, py, pw, ph, e.x + 4, e.y + 4, e.w - 8, e.h - 8)) {
        e.alive = false;
        this._dust(e.x + e.w / 2, e.y + e.h / 2, 6, '#c8c8d0');
        this.hitPlayer();
      }
    } else if (e.type === 'timeshock' && e.alive) {
      // 时间冲击波贴地：跳起来就碰不到
      if (Util.aabb(px, py, pw, ph, e.x + 6, e.y + 6, e.w - 12, e.h - 6)) this.hitPlayer();
    } else if (e.type === 'devilfire' && e.alive) {
      // 魔鬼兽的火焰弹：碰到玩家扣 1 心
      if (Util.aabb(px, py, pw, ph, e.x + 2, e.y + 2, e.w - 4, e.h - 4)) this.hitPlayer();
    } else if (e.type === 'snakebite' && e.alive && !e.hit) {
      // 帝王蛇咬击：碰到扣 1 心
      if (Util.aabb(px, py, pw, ph, e.x + 8, e.y + 6, e.w - 16, e.h - 10)) { e.hit = true; e.alive = false; this.hitPlayer(); }
    } else if (e.type === 'snakevenom' && e.alive) {
      // 毒液弹：碰到扣 1 心
      if (Util.aabb(px, py, pw, ph, e.x + 2, e.y + 2, e.w - 4, e.h - 4)) { e.alive = false; this.hitPlayer(); }
    } else if (e.type === 'snakeconstrict' && e.alive && !e.applied && e.t >= e.dur * 0.4) {
      // 缠绕：范围达到后扣 1 心 + 减速
      var cdx = (px + pw / 2) - e.x, cdy = (py + ph / 2) - e.y;
      if (cdx * cdx + cdy * cdy < e.r * e.r) { e.applied = true; this.hitPlayer(); this.player.slowT = 1.2; }
    } else if (e.type === 'spiderboss' && e.alive) {
      // 庞大的身体（含扑过来时）：碰到扣 1 心；命中盒略小于视觉（腿尖不算）
      if (Util.aabb(px, py, pw, ph, e.x + 24, e.y + 26, e.w - 48, e.h - 30)) {
        this.hitPlayer();
      }
    } else if (e.type === 'timedevourer' && e.alive) {
      if (Util.aabb(px, py, pw, ph, e.x + 14, e.y + 10, e.w - 28, e.h - 16)) {
        this.hitPlayer();
      }
    } else if ((e.type === 'emperorsnake' || e.type === 'threeheadsnake') && e.alive) {
      // 蛇怪庞大的身体：碰到扣 1 心（命中盒略小于视觉）。
      // 但被「缠绕卷死」抓住时伤害由 _snakeGrab 接管，这里跳过避免重复扣血。
      if (!e.grabbing && Util.aabb(px, py, pw, ph, e.x + 14, e.y + 10, e.w - 28, e.h - 16)) {
        this.hitPlayer();
      }
    } else if ((e.type === 'devilbeast' || e.type === 'crabbeast' || e.type === 'midspider' || e.type === 'gianttimedevourer') && e.alive) {
      // 新 Boss 庞大的身体：碰到扣 1 心（命中盒略小于视觉）
      if (Util.aabb(px, py, pw, ph, e.x + 14, e.y + 10, e.w - 28, e.h - 16)) {
        this.hitPlayer();
      }
    }
  }
  // 宇航员队友也会被光头强的攻击打到
  for (var ai = 0; ai < this.entities.length; ai++) {
    var al = this.entities[ai];
    if (al.type !== 'ally' || !al.alive) continue;
    for (var bi = 0; bi < this.entities.length; bi++) {
      var b = this.entities[bi];
      if (!b.alive || b === al) continue;
      if (b.type === 'axe' && Util.aabb(al.x + 4, al.y + 4, al.w - 8, al.h - 8, b.x + 4, b.y + 4, b.w - 8, b.h - 8)) {
        b.alive = false;
        this._dust(b.x + b.w / 2, b.y + b.h / 2, 6, '#c8c8d0');
        this._hitAlly(al);
      } else if (b.type === 'timeshock' && Util.aabb(al.x + 4, al.y + 4, al.w - 8, al.h - 8, b.x + 6, b.y + 6, b.w - 12, b.h - 6)) {
        this._hitAlly(al);
      } else if ((b.type === 'timedevourer' || b.type === 'gianttimedevourer' || b.type === 'emperorsnake' || b.type === 'threeheadsnake') && Util.aabb(al.x + 7.5, al.y + 6, al.w - 15, al.h - 9, b.x + 14, b.y + 10, b.w - 28, b.h - 16)) {
        this._hitAlly(al);
      }
    }
  }
  // 玩家的五种武器 → 敌人
  this._projectileHits(s);
};

Game.prototype._checkGoal = function (s, dt) {
  var p = this.player;
  if (s.goal === 'flag') {
    for (var i = 0; i < this.entities.length; i++) {
      var fl = this.entities[i];
      if (fl.type === 'flag' && fl.goalFlag && Util.aabb(p.x, p.y, p.w, p.h, fl.x - 21, fl.y - 9, 54, 120)) {
        this.score += 200;
        this.loadStage(this.stageIndex + 1);
        return;
      }
    }
  } else if (s.goal === 'boss') {
    // 唯一出路是打死 Boss：死亡动画放完（约 2s 胜利小节）后进入下一幕；
    // 最终 Boss（final）打死后进入「飞回地球」返航过场 → 胜利
    if (this.bossClearT > 0) {
      this.bossClearT -= dt;
      if (this.bossClearT <= 0) {
        this.bossClearT = 0;
        if (s.final) {
          this.state = 'cutscene';
          this.cutscene = { type: 'return', t: 0, dur: 4.5 };
          Sfx.returnFly();
        } else if (s.bossLeadsToSnake) {
          // 光头强恢复理智，带玩家前往蛇山寻找幕后黑手（插入过渡过场）
          this.state = 'cutscene';
          this.cutscene = { type: 'toSnakeMountain', t: 0, dur: 5.0 };
          Sfx.returnFly();
        } else {
          this.loadStage(this.stageIndex + 1);
        }
      }
    }
  }
};

Game.prototype._interactTarget = function (s) {
  var p = this.player;
  for (var i = 0; i < this.entities.length; i++) {
    var e = this.entities[i];
    if ((s.goal === 'rocket' && e.type === 'rocket' && !e.used) ||
        (s.goal === 'ship' && e.type === 'ship' && !e.used && e.landed) ||
        (s.goal === 'castle' && e.type === 'castle' && !e.used)) {
      // 交互区从物体顶部一直延伸到地面，方便小朋友走过去按 ↑
      var zx = e.x - 30, zy = e.y - 24;
      var zw = e.w + 60, zh = (s.groundY + 12) - zy;
      if (e.type === 'castle') {
        // 城堡只在发光的门口那一小段交互
        zx = e.x + e.w / 2 - 70;
        zw = 140;
      }
      if (Util.aabb(p.x, p.y, p.w, p.h, zx, zy, zw, zh)) return e;
    }
  }
  return null;
};

Game.prototype._startInteractCutscene = function (goal, target) {
  target.used = true;
  if (goal === 'rocket') {
    target.launched = true;
    target.flameT = 1;
    // 必杀技仍按原版节奏：第 4 幕登船（长角兽军团）后才解锁
    this.state = 'cutscene';
    this.cutscene = { type: 'launch', t: 0, dur: 3.0 };
    Sfx.launch();
  } else if (goal === 'ship') {
    // 登船去火星：途中解锁全部五种必杀技
    this.state = 'cutscene';
    this.cutscene = { type: 'toMars', t: 0, dur: 4.5, unlocked: false };
    Sfx.returnFly();
  } else { // castle
    this.state = 'cutscene';
    this.cutscene = { type: 'enterCastle', t: 0, dur: 1.6 };
    Sfx.castleEnter();
  }
};

// ===== 过场 =====
Game.prototype.updateCutscene = function (dt) {
  var c = this.cutscene;
  if (!c) return;
  c.t += dt;
  if (c.type === 'launch') {
    // 屏幕震动：先增后减
    this.shake = Math.max(this.shake, 9 * Math.sin(c.t * 3) * (1 - c.t / c.dur));
    if (c.t >= c.dur) {
      this.loadStage(this.stageIndex + 1);
      this.state = 'playing';
    }
  } else if (c.type === 'toMars') {
    this.shake = Math.max(this.shake, 4 * Math.sin(c.t * 4) * (1 - c.t / c.dur));
    // 过场中段亮出「解锁全部必杀技」—— 能力存在 Game 上，loadStage 时回填给玩家
    if (!c.unlocked && c.t >= c.dur * 0.55) {
      c.unlocked = true;
      this.hasWeapons = true;
      Sfx.unlockAll();
    }
    if (c.t >= c.dur) {
      this.hasWeapons = true;
      this.loadStage(this.stageIndex + 1);
      this.state = 'playing';
    }
  } else if (c.type === 'enterCastle') {
    if (c.t >= c.dur) {
      this.loadStage(this.stageIndex + 1);
      this.state = 'playing';
    }
  } else if (c.type === 'return') {
    this.shake = Math.max(this.shake, 4.5 * Math.sin(c.t * 4) * (1 - c.t / c.dur));
    if (c.t >= c.dur) {
      this.goWin();
    }
  } else if (c.type === 'toSnakeMountain') {
    this.shake = Math.max(this.shake, 4 * Math.sin(c.t * 4) * (1 - c.t / c.dur));
    if (c.t >= c.dur) {
      this.loadStage(this.stageIndex + 1);
      this.state = 'playing';
    }
  }
};

// ===== 受伤 / 死亡 =====
Game.prototype.hitPlayer = function () {
  var p = this.player;
  if (!p || !p.alive || p.invincible > 0) return;
  p.hearts--;
  Sfx.hurt();
  this._dust(p.x + p.w / 2, p.y + p.h / 2, 8, '#ff8a8a');
  if (p.hearts <= 0) {
    p.alive = false;
    this.state = 'gameover';
    Sfx.gameover();
  } else {
    p.invincible = 1.6;
    p.vy = -10.5;
    p.vx = -p.facing * 4.5;
  }
};

Game.prototype.fellOff = function () {
  var p = this.player;
  if (!p) return;
  p.hearts--;
  Sfx.hurt();
  if (p.hearts <= 0) {
    p.alive = false;
    this.state = 'gameover';
    Sfx.gameover();
  } else {
    var s = STAGES[this.stageIndex];
    p.x = s.spawn.x; p.y = s.spawn.y;
    p.vx = 0; p.vy = 0;
    p.invincible = 1.6;
    p.onGround = false;
    p.slowT = 0; p.dizzyT = 0;
  }
};

Game.prototype._dust = function (x, y, n, color) {
  for (var i = 0; i < n; i++) {
    this.entities.push(Entities.particle(x, y, {
      vx: Util.rand(-3.75, 3.75), vy: Util.rand(-5.25, -0.75),
      life: 0.5 + Math.random() * 0.3, color: color || '#d8d8e0', size: Util.randInt(3, 6)
    }));
  }
};

// ===== 绘制 =====
Game.prototype.draw = function () {
  if (!this.ctx) return;
  var ctx = this.ctx;
  ctx.save();
  ctx.clearRect(0, 0, VIEW.W, VIEW.H);
  if (this.shake > 0) {
    ctx.translate(Util.rand(-this.shake, this.shake), Util.rand(-this.shake, this.shake));
  }

  if (this.state === 'menu') {
    Render.menu(ctx, this.time);
  } else if (this.state === 'playing' || this.state === 'gameover') {
    this._drawScene(ctx);
    if (this.state === 'gameover') Render.gameover(ctx, this.score, this.time);
    else if (this.paused) Render.pause(ctx);
  } else if (this.state === 'cutscene') {
    this._drawCutscene(ctx);
  } else if (this.state === 'win') {
    Render.win(ctx, this.score, this.time);
  }
  ctx.restore();
};

Game.prototype._drawScene = function (ctx) {
  var s = STAGES[this.stageIndex];
  Render.background(ctx, s, this.camera, this.time, this.bgStars);
  // 平台
  for (var i = 0; i < this.platforms.length; i++) {
    Render.platform(ctx, this.platforms[i], this.camera, s.theme);
  }
  // 地面层：小坑与黏液
  for (var j = 0; j < this.entities.length; j++) {
    var e = this.entities[j];
    if (e.type === 'crater') Render.crater(ctx, e, this.camera);
    else if (e.type === 'slime') Render.slime(ctx, e, this.camera);
  }
  // 实体分层绘制
  for (var k = 0; k < this.entities.length; k++) {
    var e2 = this.entities[k];
    if (e2.type === 'rocket') Render.rocket(ctx, e2, this.camera, this.time);
    else if (e2.type === 'ship') Render.ship(ctx, e2, this.camera, this.time);
    else if (e2.type === 'castle') Render.castle(ctx, e2, this.camera, this.time);
    else if (e2.type === 'flag') Render.flag(ctx, e2, this.camera, this.time);
    else if (e2.type === 'snowball' && e2.alive) Render.snowball(ctx, e2, this.camera, s.groundY);
    else if (e2.type === 'house' && e2.alive) Render.house(ctx, e2, this.camera, s.groundY);
    else if (e2.type === 'poopbeast') Render.poopbeast(ctx, e2, this.camera);
    else if (e2.type === 'hornbeast') Render.hornbeast(ctx, e2, this.camera);
    else if (e2.type === 'rollbeast') Render.rollbeast(ctx, e2, this.camera);
    else if (e2.type === 'snotbeast') Render.snotbeast(ctx, e2, this.camera);
    else if (e2.type === 'snotball' && e2.alive) Render.snotball(ctx, e2, this.camera);
    else if (e2.type === 'snotworm') Render.snotworm(ctx, e2, this.camera);
    else if (e2.type === 'littlesnake' && e2.alive) Render.littlesnake(ctx, e2, this.camera, this.time);
    else if (e2.type === 'sockbeast') Render.sockbeast(ctx, e2, this.camera);
    else if (e2.type === 'stink' && e2.alive) Render.stink(ctx, e2, this.camera);
    else if (e2.type === 'webball' && e2.alive) Render.webball(ctx, e2, this.camera);
    else if (e2.type === 'axe' && e2.alive) Render.axe(ctx, e2, this.camera);
    else if (e2.type === 'timeshock' && e2.alive) Render.timeshock(ctx, e2, this.camera);
    else if (e2.type === 'spiderboss') Render.spiderboss(ctx, e2, this.camera, this.time);
    else if (e2.type === 'midspider') Render.midspider(ctx, e2, this.camera, this.time);
    else if (e2.type === 'spiderling') Render.spiderling(ctx, e2, this.camera, this.time);
    else if (e2.type === 'timedevourer') Render.timedevourer(ctx, e2, this.camera, this.time);
    else if (e2.type === 'gianttimedevourer') {
      // 巨化光头强：用缩放包裹原 timedevourer 画法，脚底为缩放中心
      ctx.save();
      var gx = e2.x - this.camera.x + e2.w / 2, gy = e2.y + e2.h;
      ctx.translate(gx, gy);
      ctx.scale(1.8, 1.8);
      ctx.translate(-gx, -gy);
      Render.timedevourer(ctx, e2, this.camera, this.time);
      ctx.restore();
    }
    else if (e2.type === 'devilbeast') Render.devilbeast(ctx, e2, this.camera, this.time);
    else if (e2.type === 'crabbeast') Render.crabbeast(ctx, e2, this.camera, this.time);
    else if (e2.type === 'emperorsnake') Render.emperorsnake(ctx, e2, this.camera, this.time);
    else if (e2.type === 'threeheadsnake') Render.threeheadsnake(ctx, e2, this.camera, this.time);
    else if (e2.type === 'snakebite' && e2.alive) Render.snakebite(ctx, e2, this.camera);
    else if (e2.type === 'snakevenom' && e2.alive) Render.snakevenom(ctx, e2, this.camera);
    else if (e2.type === 'snakeconstrict' && e2.alive) Render.snakeconstrict(ctx, e2, this.camera);
    else if (e2.type === 'ally') {
      if (e2.allyType === 'guangtouqiang') Render.guangtouqiangAlly(ctx, e2, this.camera);
      else Render.ally(ctx, e2, this.camera);
    }
    else if (e2.type === 'bullet' && e2.alive) Render.bullet(ctx, e2, this.camera);
    else if (e2.type === 'fireball' && e2.alive) Render.fireball(ctx, e2, this.camera);
    else if (e2.type === 'devilfire' && e2.alive) Render.devilfire(ctx, e2, this.camera);
    else if (e2.type === 'missile' && e2.alive) Render.missile(ctx, e2, this.camera);
    else if (e2.type === 'atombomb' && e2.alive) Render.atombomb(ctx, e2, this.camera);
    else if (e2.type === 'hydrogenbomb' && e2.alive) Render.hydrogenbomb(ctx, e2, this.camera);
    else if (e2.type === 'explosion' && e2.alive) Render.explosion(ctx, e2, this.camera);
  }
  // 玩家
  if (this.player) Render.player(ctx, this.player, this.camera);
  // 被蛇怪缠绕卷住时，在玩家身上画一圈缠绞的蛇身
  if (this.player && this.player.grabbed) Render.snakecoil(ctx, this.player, this.camera, this.time);
  // 粒子在最上层
  for (var m = 0; m < this.entities.length; m++) {
    var e3 = this.entities[m];
    if (e3.type === 'particle') Render.particle(ctx, e3, this.camera);
  }
  // HUD
  if (this.player) {
    Render.hud(ctx, this.player, this.score, s.name, this.muted, this);
    Render.tipBar(ctx, this._stageTip(s));
  }
  // Boss 胜利小节
  if (this.bossClearT > 0) {
    Render.bossClear(ctx, this.bossClearT, this.time, this.bossClearName);
  }
  // 光头强进入第二阶段横幅
  if (this.phaseBannerT > 0) {
    Render.phaseBanner(ctx, this.phaseBannerT, this.phaseBannerMsg);
  }
  // 召唤提示 / 消息
  if (this.summonMsgT > 0) {
    Render.toast(ctx, this.summonMsg);
  }
  // 晕眩绿雾（视野变模糊）
  if (this.player && this.player.dizzyT > 0) {
    ctx.fillStyle = 'rgba(110,200,90,' + (0.14 + 0.05 * Math.sin(this.time * 8)) + ')';
    ctx.fillRect(0, 0, VIEW.W, VIEW.H);
  }
  // 过渡白闪
  if (this.flashAlpha > 0) {
    ctx.fillStyle = 'rgba(255,255,255,' + this.flashAlpha + ')';
    ctx.fillRect(0, 0, VIEW.W, VIEW.H);
  }
};

// 第 4 幕的提示随击杀进度变化（告诉小朋友还差几只、飞船来了没）
Game.prototype._stageTip = function (s) {
  if (!s.needKills) return s.tip;
  if (this.killCount < s.needKills) {
    return '踩扁长角兽 ' + this.killCount + '/' + s.needKills +
           '，还差 ' + (s.needKills - this.killCount) + ' 只飞船就来！滚球兽跳过去或踩瘪';
  }
  if (!this._shipLanded) return '太棒了！飞船正在降落，等它停稳…';
  return '飞船停稳了！走到飞船旁按 ↑ 登船去火星';
};

Game.prototype._drawCutscene = function (ctx) {
  var c = this.cutscene;
  if (!c) return;
  var prog = Util.clamp(c.t / c.dur, 0, 1);
  if (c.type === 'launch') {
    Render.cutsceneLaunch(ctx, prog, STAGES[this.stageIndex], this.camera, this.time, this.bgStars, this.shake);
  } else if (c.type === 'toMars') {
    Render.cutsceneToMars(ctx, prog, this.time, this.shake);
  } else if (c.type === 'enterCastle') {
    this._drawScene(ctx);
    Render.cutsceneEnterCastle(ctx, prog, this.time);
  } else if (c.type === 'return') {
    Render.cutsceneReturn(ctx, prog, this.time, this.shake, STAGES[this.stageIndex].groundY);
  } else if (c.type === 'toSnakeMountain') {
    Render.cutsceneToSnakeMountain(ctx, prog, this.time, this.shake);
  }
};

// 暴露只读状态访问（测试用）
Game.prototype.getStageName = function () {
  return this.stageIndex < STAGES.length ? STAGES[this.stageIndex].name : '飞回地球';
};

// 挂载到全局
if (typeof window !== 'undefined') {
  window.game = new Game();
}
