// levels.js - 《杨御风：火星·月球远征》14 幕关卡数据（纯位置数据，loadStage 时构造实体）
// groundY=693 为地面顶部 y；玩家脚底对齐 groundY
// 可玩幕为 idx 0~13（第 1~14 幕）；第 14 幕「巨型时间吞噬者（光头强巨化）」是最终 Boss，
// 打败他之后进入「飞回地球」返航过场 → 胜利（见 game.js 的 loadStage/_checkGoal/goWin）
// 剧情走向（合并版 = 原版火星主线 + 新增航天/火星最高峰续集）：
//   地球发射 → 太空(陨石风暴/大便兽/长角兽军团→登船) → 火星(怪物群/大蜘蛛兽) → 神秘城堡 → 光头强(普通,中级Boss)
//   → 火星最高峰探险 → 魔鬼兽 → 大蜘蛛兽 → 大螃蟹兽 → 终极蜘蛛怪(骷髅头) → 巨型时间吞噬者(光头强巨化,最终)
var STAGES = [
  {
    // 第 1 幕：地球草地发射基地，走到火箭旁按 ↑ 发射
    name: '第 1 幕 地球出发',
    theme: 'earth',
    width: 2250,
    gravity: 1.35,
    jumpVel: 19.8,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: { x: 1905, y: 513 },
    flag: null,
    ship: null,
    castle: null,
    boss: null,
    goal: 'rocket',
    tip: '一直往右走，走到火箭旁边按 ↑ 发射升空！'
  },
  {
    // 第 2 幕：太空中下起陨石风暴 —— 雪球雨 + 房子雨，边跑边躲到旗帜
    name: '第 2 幕 太空·陨石风暴',
    theme: 'space',
    width: 4200,
    gravity: 0.6,
    jumpVel: 18.3,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 1320, y: 558, w: 180, h: 24 },
      { x: 2220, y: 510, w: 180, h: 24 },
      { x: 3120, y: 558, w: 180, h: 24 }
    ],
    snowRate: { rollDist: 560, fallDist: 460, max: 5 },
    houseDist: 620,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flag: { x: 4050, y: 588 },
    ship: null,
    castle: null,
    boss: null,
    goal: 'flag',
    tip: '天上掉雪球和房子啦！看地上的影子躲开，一直走到旗帜'
  },
  {
    // 第 3 幕：太空遇到大便兽，跳过或踩扁，走到旗帜
    name: '第 3 幕 太空·大便兽',
    theme: 'space',
    width: 3600,
    gravity: 0.6,
    jumpVel: 18.3,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 1020, y: 534, w: 180, h: 24 },
      { x: 2400, y: 534, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [
      [840, 1230],
      [1530, 1950],
      [2280, 2730],
      [2970, 3390]
    ],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flag: { x: 3480, y: 588 },
    ship: null,
    castle: null,
    boss: null,
    goal: 'flag',
    tip: '大便兽慢慢走，从它头上跳过去，踩到头还能把它压扁！'
  },
  {
    // 第 4 幕：长角兽军团！还没武器，只能踩头。踩够 60 只，飞船就降落在尽头
    name: '第 4 幕 太空·长角兽军团',
    theme: 'space',
    width: 3600,
    gravity: 0.6,
    jumpVel: 18.3,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 900, y: 540, w: 180, h: 24 },
      { x: 2100, y: 540, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [600],
    snotWorms: [],
    slimes: [],
    // 长角兽/滚球兽的出场节奏：每 hornEvery 秒来 1~2 只长角兽（场上最多 6 只），
    // 每 rollEvery 秒滚来一只滚球兽（场上最多 2 只）
    hornEvery: 1.4,
    rollEvery: 9,
    needKills: 60,
    rocket: null,
    flag: null,
    ship: { x: 3350, y: 603 },
    castle: null,
    boss: null,
    goal: 'ship',
    tip: '跳到长角兽头上踩扁它！踩够 60 只，飞船就来接你去火星'
  },
  {
    // 第 5 幕：火星红色地表，怪物群混合登场；此时已解锁五种必杀技
    name: '第 5 幕 火星·怪物群',
    theme: 'mars',
    width: 4200,
    gravity: 0.6,
    jumpVel: 18.3,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 1250, y: 536, w: 180, h: 24 },
      { x: 2350, y: 502, w: 180, h: 24 },
      { x: 3450, y: 536, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [1100, 2300, 3600],
    sockBeasts: [
      [1500, 1800],
      [3000, 3300]
    ],
    hornBeasts: [500, 1750, 2900],
    snotWorms: [
      [700, 950],
      [1350, 1560],
      [2000, 2220],
      [2600, 2850],
      [3350, 3560],
      [3850, 4050]
    ],
    slimes: [],
    rocket: null,
    flag: { x: 4080, y: 588 },
    ship: null,
    castle: null,
    boss: null,
    goal: 'flag',
    tip: '火星怪兽来啦！按 H J K L U 放必杀技打它们，走到旗帜'
  },
  {
    // 第 6 幕：火星 Boss —— 八条腿的大蜘蛛兽
    name: '第 6 幕 火星·大蜘蛛兽',
    theme: 'mars',
    width: 1600,
    gravity: 0.6,
    jumpVel: 18.3,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 450, y: 537, w: 180, h: 24 },
      { x: 966, y: 537, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flag: null,
    ship: null,
    castle: null,
    boss: { x: 800, kind: 'spiderboss' },
    goal: 'boss',
    tip: '八条腿的大蜘蛛兽！用 H J K L U 打它，看到「!」就快跳开'
  },
  {
    // 第 7 幕：打败蜘蛛后往前走，尽头是开着门的神秘城堡
    name: '第 7 幕 神秘城堡',
    theme: 'mars',
    width: 2700,
    gravity: 0.6,
    jumpVel: 18.3,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 1200, y: 536, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [1250],
    snotWorms: [
      [700, 950],
      [1550, 1800]
    ],
    slimes: [],
    rocket: null,
    flag: null,
    ship: null,
    castle: { x: 2220 },
    boss: null,
    goal: 'castle',
    tip: '前面有一座神秘的城堡！走到发光的门口，按 ↑ 进去'
  },
  {
    // 第 8 幕：城堡内部，大魔王光头强（普通体型，二阶段）。打败他后他逃往火星最高峰（奥林匹斯山）！
    name: '第 8 幕 城堡内·光头强',
    theme: 'castle',
    width: 1600,
    gravity: 0.6,
    jumpVel: 18.3,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 450, y: 537, w: 180, h: 24 },
      { x: 966, y: 537, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flag: null,
    ship: null,
    castle: null,
    boss: { x: 850, kind: 'timedevourer' },
    goal: 'boss',
    tip: '大魔王光头强！先用弱难度削他，血量过半他会生气（第二阶段更猛），小心电锯和木屑气浪。打败他后他逃往火星最高峰（奥林匹斯山）——追上去决战！'
  },
  {
    // 第 9 幕：火星最高峰（奥林匹斯山）！大雪球小雪球滚下来、房子从天上掉，跳过大便兽，穿过两面旗，躲开掉落的房子
    name: '第 9 幕 火星最高峰（奥林匹斯山探险）',
    theme: 'mars',
    width: 5400,
    gravity: 0.62,
    jumpVel: 18.4,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 760, y: 556, w: 180, h: 24 },
      { x: 1500, y: 520, w: 180, h: 24 },
      { x: 2300, y: 556, w: 180, h: 24 },
      { x: 3200, y: 520, w: 180, h: 24 },
      { x: 4100, y: 556, w: 180, h: 24 },
      { x: 4800, y: 520, w: 180, h: 24 }
    ],
    snowRate: { rollDist: 520, fallDist: 460, max: 5 },
    houseDist: 700,
    poopBeasts: [
      [1950, 2450]                  // 第一面旗之后出没的大便兽：绝对不能碰到，必须从它头上跳过去
    ],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flags: [
      { x: 1850, y: 588 },          // 第一面旗：旗后大便兽出没
      { x: 3300, y: 588 }           // 第二面旗：旗后巨大房子砸下，注意躲避
    ],
    flag: { x: 5240, y: 588 },      // 火星最高峰终点旗 → 进入魔鬼兽
    ship: null,
    castle: null,
    boss: null,
    goal: 'flag',
    tip: '光头强逃往火星最高峰（奥林匹斯山）！火星最高峰上大雪球小雪球滚下来、房子从天上掉！跳过大便兽，穿过两面旗，躲开掉落的房子，走到终点旗'
  },
  {
    // 第 10 幕：魔鬼兽（红色飞行小恶魔）
    name: '第 10 幕 魔鬼兽',
    theme: 'mars',
    width: 1500,
    gravity: 0.62,
    jumpVel: 18.4,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 380, y: 540, w: 180, h: 24 },
      { x: 940, y: 540, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flags: [],
    flag: null,
    ship: null,
    castle: null,
    boss: { x: 760, kind: 'devilbeast' },
    goal: 'boss',
    tip: '红色小恶魔魔鬼兽！它会飞、吐火球还会俯冲砸地，看到「!」就快闪开，用 H J K L U 打它'
  },
  {
    // 第 11 幕：大蜘蛛兽（八条腿，火星版）
    name: '第 11 幕 大蜘蛛兽',
    theme: 'mars',
    width: 1600,
    gravity: 0.62,
    jumpVel: 18.4,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 450, y: 537, w: 180, h: 24 },
      { x: 966, y: 537, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flags: [],
    flag: null,
    ship: null,
    castle: null,
    boss: { x: 800, kind: 'spiderboss' },
    goal: 'boss',
    tip: '八条腿的大蜘蛛兽！用 H J K L U 打它，看到「!」就快跳开'
  },
  {
    // 第 12 幕：大螃蟹兽（一只巨钳的螃蟹）
    name: '第 12 幕 大螃蟹兽',
    theme: 'mars',
    width: 1600,
    gravity: 0.62,
    jumpVel: 18.4,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 450, y: 537, w: 180, h: 24 },
      { x: 966, y: 537, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flags: [],
    flag: null,
    ship: null,
    castle: null,
    boss: { x: 800, kind: 'crabbeast' },
    goal: 'boss',
    tip: '大螃蟹兽举着一只巨钳砸地（贴地冲击波，跳起来躲），还会扔泡泡，用 H J K L U 打它'
  },
  {
    // 第 13 幕：终极蜘蛛怪（骷髅头蜘蛛兽）—— 打完大螃蟹兽后、挑战最终 Boss 前的关卡
    name: '第 13 幕 终极蜘蛛怪（骷髅头）',
    theme: 'mars',
    width: 1600,
    gravity: 0.62,
    jumpVel: 18.4,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 450, y: 537, w: 180, h: 24 },
      { x: 966, y: 537, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flags: [],
    flag: null,
    ship: null,
    castle: null,
    boss: { x: 800, kind: 'midspider' },
    goal: 'boss',
    tip: '骷髅头蜘蛛兽！比大蜘蛛兽更凶，用 H J K L U 打它，看到「!」就快跳开'
  },
  {
    // 第 14 幕：巨型时间吞噬者（最终 Boss，光头强巨化）
    name: '第 14 幕 巨型时间吞噬者（光头强）',
    theme: 'mars',
    width: 1700,
    gravity: 0.62,
    jumpVel: 18.4,
    groundY: 693,
    spawn: { x: 105, y: 600 },
    platforms: [
      { x: 450, y: 537, w: 180, h: 24 },
      { x: 1040, y: 537, w: 180, h: 24 }
    ],
    snowRate: null,
    houseDist: 0,
    poopBeasts: [],
    snotBeasts: [],
    sockBeasts: [],
    hornBeasts: [],
    snotWorms: [],
    slimes: [],
    rocket: null,
    flags: [],
    flag: null,
    ship: null,
    castle: null,
    boss: { x: 850, kind: 'gianttimedevourer' },
    final: true,                   // 打败他之后：乘外星飞船飞回地球（返航过场）→ 胜利
    goal: 'boss',
    tip: '最终大魔王——巨化的光头强！先用弱难度削他，血量过半他会生气（第二阶段更猛）——这时按 B 召唤宇航员队友一起打！小心电锯和木屑气浪'
  }
];
