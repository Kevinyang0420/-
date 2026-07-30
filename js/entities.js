// entities.js - 游戏实体工厂（杨御风、雪球、房子、大便兽、长角兽、滚球兽、鼻涕兽、鼻涕虫、
//               臭袜子兽、蛛丝球、大蜘蛛兽、电锯、电锯气浪、光头强、宇航员队友、
//               子弹、火球、大导弹、原子弹、氢弹、爆炸、火箭、飞船、旗帜、城堡、粒子）
// 全部为纯数据对象；更新逻辑集中在 game.js，绘制在 render.js

// 可召唤的宇航员队友配色（最多同时 2 名，按召唤顺序取用）
var ALLY_DEFS = [
  { name: '飞飞', suit: '#3a6fd9', trim: '#aadcff' },
  { name: '童童', suit: '#2fae6a', trim: '#bff0d0' }
];

var Entities = {

  // 杨御风：太空战士（蓝红战甲 + 透明头盔）
  player: function (x, y) {
    return {
      type: 'player', x: x, y: y, vx: 0, vy: 0, w: 39, h: 63,
      hearts: 3, maxHearts: 3, facing: 1, onGround: false,
      invincible: 0, anim: 0, alive: true, jumpCut: false,
      slowT: 0, dizzyT: 0, bubbleAcc: 0,
      hasWeapons: false,                     // 五种必杀技（第 4 幕登船解锁，跨关保留，由 Game 回填）
      cd: { bullet: 0, fireball: 0, missile: 0, atombomb: 0, hydrogenbomb: 0 },   // 各武器独立冷却
      spawnX: x, spawnY: y, prevBottom: y + 63
    };
  },

  // 宇航员队友：被玩家召唤来一起打光头强（AI 跟随 + 朝 Boss 射子弹）。
  // 有 3 颗心，会被光头强的攻击打到；被打倒后消失，可再次召唤补位。
  ally: function (x, y, def, side) {
    return {
      type: 'ally', x: x, y: y, vx: 0, vy: 0, w: 39, h: 63,
      hearts: 3, maxHearts: 3, facing: 1, onGround: false,
      invincible: 0, anim: 0, alive: true, deadT: 0,
      shootT: Util.rand(0.4, 1.2),
      name: def.name, suit: def.suit, trim: def.trim,
      side: side || 1
    };
  },

  // 雪球：mode 'roll' 从右滚来；mode 'fall' 从天上砸下
  snowball: function (x, y, mode, r) {
    r = r || Util.randInt(27, 45);
    return {
      type: 'snowball', x: x, y: y, vx: mode === 'roll' ? -Util.rand(2.1, 3.9) : 0,
      vy: mode === 'fall' ? Util.rand(3.0, 5.25) : 0,
      w: r * 2, h: r * 2, r: r, mode: mode, spin: 0, alive: true
    };
  },

  // 房子：从天上砸下来的卡通小房子（落地砸出大坑，不能踩）
  house: function (x, y) {
    return {
      type: 'house', x: x, y: y, vx: 0, vy: Util.rand(3.2, 4.6),
      w: 96, h: 84, wob: Util.rand(0, 6.28), alive: true
    };
  },

  // 大便兽：在 x1~x2 之间地面巡逻，可踩头压扁
  poopbeast: function (x1, x2, groundY) {
    var x = (x1 + x2) / 2;
    return {
      type: 'poopbeast', x: x, y: groundY - 51, vx: 1.65, w: 66, h: 51,
      x1: x1, x2: x2, spin: 0, alive: true, deadT: 0, blink: 0
    };
  },

  // 长角兽：头长两只大角的橙红色小兽，慢悠悠朝玩家走，只能踩头消灭（第 4 幕要踩 60 只）
  hornbeast: function (x, groundY) {
    return {
      type: 'hornbeast', x: x, y: groundY - 48, vx: 0, w: 54, h: 48,
      dir: -1, speed: 1.6, anim: Util.rand(0, 6.28), alive: true, deadT: 0
    };
  },

  // 滚球兽：缩成球一路滚过来的尖刺小兽；跳过去躲开，也可以踩瘪它
  rollbeast: function (x, groundY, dir) {
    return {
      type: 'rollbeast', x: x, y: groundY - 56, vx: dir * 3.3, vy: 0, w: 56, h: 56, r: 28,
      spin: 0, life: 14, alive: true, deadT: 0
    };
  },

  // 鼻涕兽：几乎原地不动（极慢左右挪），每隔约 2.5 秒朝玩家吐鼻涕球
  snotbeast: function (x, groundY) {
    return {
      type: 'snotbeast', x: x, y: groundY - 48, vx: 0.45, w: 66, h: 48,
      x1: x - 45, x2: x + 45, facing: -1, breathe: Util.rand(0, 6.28),
      spitT: Util.rand(1.2, 2.2), alive: true, deadT: 0
    };
  },

  // 鼻涕球：小的黄绿色黏球，低速平飞、会下坠，落地变成一摊黏液
  snotball: function (x, y, dir) {
    return {
      type: 'snotball', x: x, y: y, vx: dir * 3.9, vy: -2.4,
      w: 24, h: 24, r: 12, spin: 0, life: 5, alive: true
    };
  },

  // 黏液：留在地面约 4 秒；踩到不扣心，但会减速、跳矮 1.5 秒
  slime: function (x, y, life) {
    life = life || 4;
    return {
      type: 'slime', x: x, y: y, vx: 0, vy: 0, w: 90, h: 14,
      life: life, maxLife: life, bubble: 0, alive: true
    };
  },

  // 鼻涕虫：贴地慢慢爬的黄绿色小虫，在 x1~x2 之间来回；个头矮，好踩
  snotworm: function (x1, x2, groundY) {
    var x = (x1 + x2) / 2;
    return {
      type: 'snotworm', x: x, y: groundY - 22, vx: 0.9, w: 44, h: 22,
      x1: x1, x2: x2, anim: Util.rand(0, 6.28), alive: true, deadT: 0
    };
  },

  // 臭袜子兽：蹦跳式前进，在 x1~x2 来回；每次落地放出一圈臭气
  sockbeast: function (x1, x2, groundY) {
    var x = (x1 + x2) / 2;
    return {
      type: 'sockbeast', x: x, y: groundY - 66, vx: 0, vy: 0, w: 48, h: 66,
      dir: 1, x1: x1, x2: x2, onGround: true, idleT: 0.6,
      anim: Util.rand(0, 6.28), alive: true, deadT: 0
    };
  },

  // 臭气：从袜底向外扩散的绿圈（约 1.2 秒）；罩到不扣心，但会晕：方向反向 1.2 秒
  stink: function (cx, groundY) {
    return {
      type: 'stink', x: cx, y: groundY - 10, vx: 0, vy: 0, r: 12, maxR: 150,
      t: 0, dur: 1.2, applied: false, alive: true
    };
  },

  // 蛛丝球：大蜘蛛兽吐出的白色黏球，抛过来砸人，落地散掉
  webball: function (x, y, dir) {
    return {
      type: 'webball', x: x, y: y, vx: dir * Util.rand(2.8, 3.6), vy: -5.5,
      w: 26, h: 26, r: 13, spin: 0, life: 4, alive: true
    };
  },

  // 大蜘蛛兽（火星 Boss）：八条腿的大蜘蛛，在地上左右爬，会吐蛛丝球、还会跳过来扑人
  spiderboss: function (x, groundY) {
    return {
      type: 'spiderboss', x: x - 110, y: groundY - 150, vx: 0, vy: 0, w: 220, h: 150,
      hp: 60, maxHp: 60, dir: 1,
      x1: x - 430, x2: x + 430,               // 活动范围（只守自己的地盘）
      anim: 0, spitT: 2.2, pounceT: 5.0, windupT: 0, pouncing: false,
      hurtT: 0, fallT: 0, alive: true
    };
  },

  // 电锯：光头强扔出的旋转小电锯，划一道弧线飞过来（内部类型仍叫 axe）
  axe: function (x, y, dir) {
    return {
      type: 'axe', x: x, y: y, vx: dir * 5.2, vy: -8.5, w: 34, h: 34,
      spin: 0, life: 3.5, alive: true
    };
  },

  // 电锯气浪：贴地向一边扩散的木屑气浪，跳起来就能躲过（内部类型仍叫 timeshock）
  timeshock: function (x, groundY, dir) {
    return {
      type: 'timeshock', x: x + dir * 44 - 20, y: groundY - 58, vx: dir * 6.6, vy: 0,
      w: 40, h: 58, life: 1.2, alive: true
    };
  },

  // 光头强（最终 Boss）：戴橙黄毛线帽、穿绿色背带工装、大鼻子、络腮胡茬的伐木工反派。
  // 会朝玩家慢慢逼近、扔电锯、放电锯气浪，还会一溜烟窜到别处（跑得飞快！）
  // 血量过半进入第二阶段（生气）：速度翻倍、双电锯、更快的气浪/瞬移，还会冲撞。
  // phase: 1=平常(弱) 2=生气(猛)；transitionT>0 表示正在变身停顿。
  // 注：内部类型标识仍沿用 timedevourer，避免牵动关卡数据与测试
  timedevourer: function (x, groundY) {
    return {
      type: 'timedevourer', x: x - 60, y: groundY - 156, vx: 0, vy: 0, w: 120, h: 156,
      hp: 80, maxHp: 80, dir: -1,
      x1: x - 380, x2: x + 380,               // 活动范围
      anim: 0, axeT: 2.4, shockT: 5.0, blinkT: 7.0,
      blinkOut: 0, blinkIn: 0,                // 瞬移：先淡出再淡入
      phase: 1, transitionT: 0, steamT: 0,    // 两阶段
      dashCd: 5.0, dashing: 0, dashDir: 1,    // 第二阶段冲撞
      hurtT: 0, fallT: 0, alive: true
    };
  },

  // ===== 五种必杀技（H/J/K/L/U）=====

  // H 子弹：沿 facing 方向快速平飞的小弹丸（几乎无重力），伤害 1
  bullet: function (x, y, dir) {
    return {
      type: 'bullet', x: x, y: y, vx: dir * 15, vy: 0, w: 18, h: 8,
      life: 1.4, alive: true
    };
  },

  // J 火球：带重力走一道大抛物线（出手先高高抛起）、落地弹跳，伤害 3
  fireball: function (x, y, dir) {
    return {
      type: 'fireball', x: x, y: y, vx: dir * 8.4, vy: -13, w: 26, h: 26, r: 13,
      bounces: 0, life: 2.5, spin: 0, alive: true
    };
  },

  // 魔鬼兽吐出的火焰弹（敌方投射物，会伤玩家、不会伤 Boss 自己）
  // 注意：type 不能叫 'fireball'（那是玩家武器，会在 _projectileHits 里被当成玩家弹反伤 Boss）
  devilfire: function (x, y, dir) {
    return {
      type: 'devilfire', x: x, y: y, vx: dir * 5.6, vy: 0, w: 24, h: 24, r: 12,
      life: 3.0, spin: 0, alive: true
    };
  },

  // K 大导弹：又快又大、直飞穿屏，伤害 6
  missile: function (x, y, dir) {
    return {
      type: 'missile', x: x, y: y, vx: dir * 21, vy: 0, w: 44, h: 16,
      life: 1.8, puff: 0, alive: true
    };
  },

  // L 原子弹：抛出去，落地或命中炸开大爆炸（半径 150），范围内伤害 12
  atombomb: function (x, y, dir) {
    return {
      type: 'atombomb', x: x, y: y, vx: dir * 7.5, vy: -12, w: 30, h: 30, r: 15,
      spin: 0, life: 3, boomR: 150, boomDmg: 12, alive: true
    };
  },

  // U 氢弹：最强，炸开超大爆炸（半径 280，接近全屏），范围内伤害 25
  hydrogenbomb: function (x, y, dir) {
    return {
      type: 'hydrogenbomb', x: x, y: y, vx: dir * 6.5, vy: -13, w: 36, h: 36, r: 18,
      spin: 0, life: 3, boomR: 280, boomDmg: 25, alive: true
    };
  },

  // 爆炸：一圈由小变大的冲击光环（伤害在生成瞬间已由 game.js 结算，这里纯视觉，约 0.5 秒）
  explosion: function (cx, cy, maxR) {
    return {
      type: 'explosion', x: cx, y: cy, vx: 0, vy: 0, r: 10, maxR: maxR,
      t: 0, dur: 0.5, alive: true
    };
  },

  // ===== 场景交互 =====

  rocket: function (x, y) {
    return { type: 'rocket', x: x, y: y, w: 81, h: 180, launched: false, used: false, flameT: 0 };
  },

  // 飞船：第 4 幕踩够 60 只长角兽后从天上降落（landing -> landed 后才能登船）
  ship: function (x, y) {
    return { type: 'ship', x: x, y: y, w: 144, h: 90, used: false, bob: 0,
             landing: false, landed: true };
  },

  // 神秘城堡：开着门的卡通城堡，走到发光的门口按 ↑ 进入
  castle: function (x, groundY) {
    return { type: 'castle', x: x, y: groundY - 270, w: 300, h: 270, used: false, glow: 0, alive: true };
  },

  flag: function (x, y) {
    return { type: 'flag', x: x, y: y, w: 12, h: 105, wave: 0 };
  },

  particle: function (x, y, opts) {
    opts = opts || {};
    return {
      type: 'particle', x: x, y: y,
      vx: opts.vx != null ? opts.vx : Util.rand(-3, 3),
      vy: opts.vy != null ? opts.vy : Util.rand(-4.5, -1.5),
      life: opts.life || 0.6, maxLife: opts.life || 0.6,
      color: opts.color || '#fff', size: opts.size || 4.5,
      gravity: opts.gravity != null ? opts.gravity : 0.225
    };
  },

  // 可视小坑（雪球/房子砸出）
  crater: function (x, y) {
    return { type: 'crater', x: x, y: y, r: Util.randInt(15, 27), life: 6 };
  },

  // ===== 航天版新增 Boss =====

  // 魔鬼兽（第 4 幕 Boss）：红色飞行小恶魔，头顶双角、身后尖尾、一对小蝙蝠翅、大嘴獠牙。
  // 会悬浮逼近玩家、吐火焰弹，并周期性俯冲砸地。
  devilbeast: function (x, groundY) {
    return {
      type: 'devilbeast', x: x - 65, y: groundY - 210, vx: 0, vy: 0, w: 130, h: 130,
      hp: 60, maxHp: 60, dir: -1,
      x1: x - 420, x2: x + 420,
      baseY: groundY - 210,              // 悬浮基准高度（脚底离地约 80px）
      anim: 0, fireT: 1.8, diveT: 4.5, windupT: 0, diving: false,
      hurtT: 0, fallT: 0, alive: true
    };
  },

  // 大螃蟹兽（第 6 幕 Boss）：红色大螃蟹，八条短腿，两只大钳，其中一只特别巨大。
  // 会横向爬行逼近玩家、举起巨钳砸地震出震荡波（跳起可躲）、并往外扔泡泡。
  crabbeast: function (x, groundY) {
    return {
      type: 'crabbeast', x: x - 100, y: groundY - 120, vx: 0, vy: 0, w: 200, h: 120,
      hp: 80, maxHp: 80, dir: -1,
      x1: x - 400, x2: x + 400,
      anim: 0, smashT: 3.0, bubbleT: 2.0, windupT: 0,
      hurtT: 0, fallT: 0, alive: true
    };
  },

  // 中级蜘蛛兽（骷髅头蜘蛛兽，第 7 幕 Boss）：比大蜘蛛兽更大，头胸部是一颗骷髅头。
  // 行为与大蜘蛛兽一致（复用 _updateSpider）：爬行逼近、吐骷髅弹、蓄力后扑击。
  midspider: function (x, groundY) {
    return {
      type: 'midspider', x: x - 110, y: groundY - 170, vx: 0, vy: 0, w: 220, h: 170,
      hp: 90, maxHp: 90, dir: 1,
      x1: x - 440, x2: x + 440,
      anim: 0, spitT: 2.2, pounceT: 4.8, windupT: 0, pouncing: false,
      hurtT: 0, fallT: 0, alive: true
    };
  },

  // 巨型时间吞噬者（最终 Boss：光头强巨化版，体型非常巨大）。外形、配色、两阶段机制
  // 与原光头强完全一致，只是 w/h 放大近 1.8 倍。复用 _updateTimeDevourer 的 AI；
  // 渲染时用缩放包裹原 timedevourer 画法，因此无需单独绘制函数。
  gianttimedevourer: function (x, groundY) {
    return {
      type: 'gianttimedevourer', x: x - 108, y: groundY - 280, vx: 0, vy: 0, w: 216, h: 280,
      hp: 160, maxHp: 160, dir: -1,
      x1: x - 360, x2: x + 360,
      anim: 0, axeT: 2.4, shockT: 5.0, blinkT: 7.0,
      blinkOut: 0, blinkIn: 0,
      phase: 1, transitionT: 0, steamT: 0,
      dashCd: 5.0, dashing: 0, dashDir: 1,
      hurtT: 0, fallT: 0, alive: true
    };
  }
};
