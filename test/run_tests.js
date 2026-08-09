// test/run_tests.js - Node 无头自测（零依赖，仅用内建 assert + vm + fs）
// 《杨御风：航天远征》验收测试；通过则打印 ALL TESTS PASSED 并以退出码 0 退出。
var assert = require('assert');
var fs = require('fs');
var path = require('path');
var vm = require('vm');

// ===== 1. 构造最小浏览器环境 mock（window/document）=====
// window 指向 global 自身，使 window.game / window.requestAnimationFrame 可用
global.window = global;
global.performance = global.performance || { now: function () { return Date.now(); } };
global.document = {
  addEventListener: function () {},
  getElementById: function () { return null; }
};
// requestAnimationFrame 兜底（测试不依赖主循环，但保证脚本可调用）
if (!global.requestAnimationFrame) {
  global.requestAnimationFrame = function (cb) { return setTimeout(function () { cb(performance.now()); }, 16); };
}

// ===== 2. 按依赖顺序加载全部 js（vm.runInThisContext 使顶层 var 泄漏为全局，模拟浏览器 <script>）=====
var JS_DIR = path.join(__dirname, '..', 'js');
var FILES = ['util', 'input', 'audio', 'entities', 'levels', 'render', 'game'];
FILES.forEach(function (name) {
  var src = fs.readFileSync(path.join(JS_DIR, name + '.js'), 'utf8');
  vm.runInThisContext(src, { filename: name + '.js' });
});

var game = global.game;
var Entities = global.Entities;
var Input = global.Input;

// ===== 测试运行器 =====
var passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log('  ✓ ' + name); }
  catch (e) { failed++; console.log('  ✗ ' + name + '\n      ' + (e && e.message ? e.message : e)); }
}
function stepFrames(n, dt) { dt = dt || (1 / 60); for (var i = 0; i < n; i++) game.step(dt); }
function settle() { stepFrames(20); } // 让玩家落回地面
function clearKeys() { Input.reset(); }
function findEntity(type) {
  return game.entities.filter(function (e) { return e.type === type; })[0];
}
function countType(type) {
  return game.entities.filter(function (e) { return e.type === type; }).length;
}

// ===== 3. 测试用例 =====

test('脚本全部加载并实例化 window.game', function () {
  assert.ok(game, 'window.game 应存在');
  assert.strictEqual(game.state, 'menu', '初始状态应为 menu');
  assert.strictEqual(global.VIEW.W, 1440, 'VIEW.W 应为 1440');
  assert.strictEqual(global.VIEW.H, 810, 'VIEW.H 应为 810');
  assert.strictEqual(global.STAGES.length, 17, '应有 17 个可玩幕（原版火星主线 8 幕 + 新增月球续集 6 幕 + 蛇山终章 3 幕）');
});

test('只读状态字段齐全（含 hasWeapons / killCount）', function () {
  game.startNewGame();
  assert.strictEqual(game.state, 'playing');
  assert.strictEqual(game.stageIndex, 0);
  var p = game.player;
  ['x', 'y', 'vx', 'vy', 'hearts', 'hasWeapons'].forEach(function (k) {
    assert.ok(k in p, 'player 应含 ' + k);
  });
  assert.strictEqual(p.hasWeapons, false, '新游戏玩家未解锁必杀技（地球发射前）');
  assert.strictEqual(game.hasWeapons, false, '新游戏 Game 未解锁必杀技');
  assert.strictEqual(game.killCount, 0, '新游戏击杀数为 0');
  assert.ok(Array.isArray(game.entities), 'entities 应为数组');
  assert.ok(game.entities.some(function (e) { return e.type === 'rocket' && typeof e.x === 'number'; }),
    '第 1 幕应含火箭实体（含 type/x）');
});

test('模拟按键让玩家右移', function () {
  game.startNewGame();
  settle();
  var x0 = game.player.x;
  game.pressKey('ArrowRight');
  stepFrames(30);
  game.releaseKey('ArrowRight');
  assert.ok(game.player.x > x0 + 5, '按右键后 x 应增加 (' + x0 + ' -> ' + game.player.x + ')');
  assert.strictEqual(game.player.facing, 1);
});

test('跳跃后能落回地面', function () {
  game.startNewGame();
  settle();
  assert.ok(game.player.onGround, '起跳前应在地面上');
  game.pressKey('Space');
  game.step(1 / 60);          // 起跳帧
  assert.ok(game.player.vy < 0, '起跳后 vy 应为负');
  game.releaseKey('Space');
  stepFrames(140);            // 上升 + 下落
  assert.ok(game.player.onGround, '最终应落回地面');
  assert.ok(Math.abs((game.player.y + game.player.h) - 693) < 1, '脚底应贴回地面 y=693');
});

test('第 1 幕：走到火箭旁按 ↑ 发射升空，过场后进入第 2 幕（月球）', function () {
  game.startNewGame();
  settle();
  var p = game.player;
  p.x = 1900; p.y = 600; p.vy = 0; p.onGround = true;   // 站到火箭旁
  game.pressKey('ArrowUp');
  game.step(1 / 60);
  game.releaseKey('ArrowUp');
  assert.strictEqual(game.state, 'cutscene', '按 ↑ 进入火箭应触发发射过场');
  assert.strictEqual(game.cutscene.type, 'launch');
  stepFrames(220);                                       // 等待发射过场（>3s）
  assert.strictEqual(game.state, 'playing');
  assert.strictEqual(game.stageIndex, 1, '应进入第 2 幕（太空·陨石风暴）');
  assert.strictEqual(game.hasWeapons, false, '发射后尚未解锁（要到第 4 幕登船才解锁）');
});

// ===== 第 2 幕：月球探险（雪球/房子/大便兽/两面旗）=====

test('房子雨：house 会从天上砸下，落地消失砸出坑', function () {
  game.debugGotoStage(8);
  settle();
  var p = game.player;
  var h = Entities.house(p.x + 300, 100);
  game.entities.push(h);
  assert.strictEqual(h.type, 'house');
  stepFrames(160);   // 一路下落直到砸地
  assert.strictEqual(h.alive, false, '房子落地后应消失');
  assert.ok(game.entities.some(function (e) { return e.type === 'crater'; }), '落地应砸出坑');
});

test('房子砸到玩家扣 1 颗心', function () {
  game.debugGotoStage(8);
  settle();
  var p = game.player;
  p.invincible = 0;
  var h0 = p.hearts;
  // 房子 h=84：摆在半空与玩家身体重叠、但底部仍高于地面（否则同帧就落地消失来不及砸人）
  game.entities.push(Entities.house(p.x - 20, p.y - 34));
  game.step(1 / 60);
  assert.strictEqual(p.hearts, h0 - 1, '被房子砸到应扣 1 颗心');
  assert.ok(p.invincible > 0, '受伤后应短暂无敌');
});

test('雪球碰撞扣 1 颗心', function () {
  game.debugGotoStage(8);
  settle();
  var h0 = game.player.hearts;
  game.entities.push(Entities.snowball(game.player.x, game.player.y, 'roll', 30));
  game.step(1 / 60);
  assert.strictEqual(game.player.hearts, h0 - 1, '碰雪球应扣 1 颗心');
});

// ===== 怪兽基础行为（手动投放，不依赖具体关卡内容）=====

test('新怪兽/武器工厂 type 字符串与字段符合约定', function () {
  var samples = [
    Entities.house(0, 0), Entities.hornbeast(0, 693), Entities.rollbeast(0, 693, -1),
    Entities.snotworm(0, 100, 693), Entities.webball(0, 0, 1), Entities.axe(0, 0, 1),
    Entities.timeshock(0, 693, 1), Entities.castle(0, 693),
    Entities.bullet(0, 0, 1), Entities.fireball(0, 0, 1), Entities.missile(0, 0, 1),
    Entities.atombomb(0, 0, 1), Entities.hydrogenbomb(0, 0, 1), Entities.explosion(0, 0, 150),
    Entities.spiderboss(800, 693), Entities.timedevourer(800, 693),
    Entities.devilbeast(800, 693), Entities.crabbeast(800, 693),
    Entities.midspider(800, 693), Entities.gianttimedevourer(800, 693)
  ];
  var expectTypes = ['house', 'hornbeast', 'rollbeast', 'snotworm', 'webball', 'axe',
    'timeshock', 'castle', 'bullet', 'fireball', 'missile', 'atombomb', 'hydrogenbomb',
    'explosion', 'spiderboss', 'timedevourer', 'devilbeast', 'crabbeast', 'midspider', 'gianttimedevourer'];
  samples.forEach(function (e, i) {
    assert.strictEqual(e.type, expectTypes[i], '第 ' + i + ' 个工厂 type 应为 ' + expectTypes[i]);
    ['type', 'x', 'y', 'alive'].forEach(function (k) {
      assert.ok(k in e, e.type + ' 应含字段 ' + k);
    });
  });
  assert.strictEqual(Entities.spiderboss(800, 693).hp, 60, '大蜘蛛兽初始 hp 应为 60');
  assert.strictEqual(Entities.devilbeast(800, 693).hp, 60, '魔鬼兽初始 hp 应为 60');
  assert.strictEqual(Entities.crabbeast(800, 693).hp, 80, '大螃蟹兽初始 hp 应为 80');
  assert.strictEqual(Entities.midspider(800, 693).hp, 90, '中级蜘蛛兽初始 hp 应为 90');
  assert.strictEqual(Entities.gianttimedevourer(800, 693).hp, 160, '巨型时间吞噬者初始 hp 应为 160');
});

test('踩大便兽头顶可消灭它并得分', function () {
  game.debugGotoStage(8);
  var beast = findEntity('poopbeast');
  assert.ok(beast, '第 9 幕（月球探险）应有大便兽');
  var p = game.player;
  var score0 = game.score;
  p.x = beast.x;
  p.y = beast.y - p.h - 1;
  p.vy = 3;
  p.invincible = 0;
  game.step(1 / 60);
  assert.strictEqual(beast.alive, false, '踩头后大便兽应被消灭');
  assert.ok(game.score > score0, '应得分');
  assert.ok(p.vy < 0, '踩中后应弹起');
});

test('踩死长角兽 killCount+1，旁边的长角兽会连带（每只都计数）', function () {
  game.debugGotoStage(0);
  settle();
  assert.strictEqual(game.killCount, 0);
  var p = game.player;
  // 放两只挨在一起的长角兽
  var a = Entities.hornbeast(1500, 693);
  var b = Entities.hornbeast(1560, 693);
  game.entities.push(a);
  game.entities.push(b);
  p.x = a.x + 5;
  p.y = a.y - p.h - 1;
  p.vy = 3;
  p.invincible = 0;
  game.step(1 / 60);
  assert.strictEqual(a.alive, false, '踩头后长角兽应被消灭');
  assert.strictEqual(b.alive, false, '旁边的长角兽应被连带消灭');
  assert.strictEqual(game.killCount, 2, 'killCount 应为 2（踩 1 + 连带 1）');
});

test('长角兽 / 滚球兽 / 鼻涕虫 碰到玩家扣 1 心', function () {
  // 长角兽（从侧面碰，不是踩）
  game.debugGotoStage(0);
  settle();
  var p = game.player;
  var h0 = p.hearts;
  game.entities.push(Entities.hornbeast(p.x + 5, 693));
  game.step(1 / 60);
  assert.strictEqual(p.hearts, h0 - 1, '被长角兽碰到应扣 1 颗心');
  // 滚球兽
  game.debugGotoStage(0);
  settle();
  p = game.player;
  h0 = p.hearts;
  game.entities.push(Entities.rollbeast(p.x + 4, 693, -1));
  game.step(1 / 60);
  assert.strictEqual(p.hearts, h0 - 1, '被滚球兽滚到应扣 1 颗心');
  // 鼻涕虫
  game.debugGotoStage(0);
  settle();
  p = game.player;
  p.invincible = 0;
  h0 = p.hearts;
  var sw = Entities.snotworm(p.x - 40, p.x + 40, 693);
  sw.y = p.y + p.h - sw.h;   // 贴玩家脚边（侧面碰，不是踩）
  game.entities.push(sw);
  game.step(1 / 60);
  assert.strictEqual(p.hearts, h0 - 1, '被鼻涕虫碰到应扣 1 颗心');
});

// ===== 五种必杀技 =====

test('未解锁前按 H/J/K/L/U 全部无效（地球发射前）', function () {
  game.debugGotoStage(0);   // 第 1 幕：地球，未解锁必杀技
  settle();
  clearKeys();
  assert.strictEqual(game.player.hasWeapons, false);
  var keys = ['KeyH', 'KeyJ', 'KeyK', 'KeyL', 'KeyU'];
  var types = ['bullet', 'fireball', 'missile', 'atombomb', 'hydrogenbomb'];
  for (var i = 0; i < keys.length; i++) {
    game.pressKey(keys[i]);
    game.step(1 / 60);
    game.releaseKey(keys[i]);
    assert.ok(!findEntity(types[i]), '未解锁时按 ' + keys[i] + ' 不应产生 ' + types[i]);
  }
});

test('解锁后按 H/J/K/L/U 各自产生对应 type 的投射物', function () {
  game.debugGotoStage(9);   // 第 3 幕起已解锁（发射即解锁）
  settle();
  clearKeys();
  assert.strictEqual(game.hasWeapons, true, 'debug 跳到第 3 幕应已解锁');
  assert.strictEqual(game.player.hasWeapons, true);
  var cases = [
    ['KeyH', 'bullet'], ['KeyJ', 'fireball'], ['KeyK', 'missile'],
    ['KeyL', 'atombomb'], ['KeyU', 'hydrogenbomb']
  ];
  for (var i = 0; i < cases.length; i++) {
    game.player.cd[cases[i][1]] = 0;   // 清掉冷却，逐个测
    game.pressKey(cases[i][0]);
    game.step(1 / 60);
    game.releaseKey(cases[i][0]);
    assert.ok(findEntity(cases[i][1]), '按 ' + cases[i][0] + ' 应产生 ' + cases[i][1]);
    assert.ok(game.player.cd[cases[i][1]] > 0, cases[i][1] + ' 应有冷却');
  }
});

test('子弹冷却独立：0.15s 内连按只出一发，过后能再发', function () {
  game.debugGotoStage(9);
  settle();
  clearKeys();
  game.pressKey('KeyH');
  game.step(1 / 60);
  game.releaseKey('KeyH');
  assert.strictEqual(countType('bullet'), 1, '按一次应出一发子弹');
  game.pressKey('KeyH');
  game.step(1 / 60);
  game.releaseKey('KeyH');
  assert.strictEqual(countType('bullet'), 1, '冷却未过连按不应再出');
  stepFrames(12);   // > 0.15s
  game.pressKey('KeyH');
  game.step(1 / 60);
  game.releaseKey('KeyH');
  assert.strictEqual(countType('bullet'), 2, '冷却过后应能再发');
});

test('武器命中普通怪兽能消灭它并得分（子弹/导弹）', function () {
  game.debugGotoStage(8);
  var beast = findEntity('poopbeast');
  assert.ok(beast);
  game.hasWeapons = true; game.player.hasWeapons = true;
  var score0 = game.score;
  game.entities.push(Entities.bullet(beast.x + 10, beast.y + 10, 1));
  game.step(1 / 60);
  assert.strictEqual(beast.alive, false, '子弹命中大便兽应消灭它');
  assert.ok(game.score > score0, '消灭应得分');
  // 导弹打手动投放的鼻涕兽
  game.debugGotoStage(8);
  var p = game.player;
  var snot = Entities.snotbeast(p.x + 300, 693);
  game.entities.push(snot);
  assert.ok(snot, '应已投放鼻涕兽');
  game.entities.push(Entities.missile(snot.x + 10, snot.y + 10, 1));
  game.step(1 / 60);
  assert.strictEqual(snot.alive, false, '导弹命中鼻涕兽应消灭它');
});

test('原子弹命中生成 explosion 并对范围内敌人造成 AoE 伤害', function () {
  game.debugGotoStage(8);
  settle();
  var p = game.player;
  // 清掉本幕预设的怪，避免爆炸连带炸到它们污染 killCount（只保留下面 3 只测试用的）
  game.entities = game.entities.filter(function (e) {
    return ['hornbeast', 'rollbeast', 'snotworm', 'snotbeast', 'sockbeast', 'poopbeast'].indexOf(e.type) < 0;
  });
  // 两只在爆炸半径内，一只在半径外
  var a = Entities.hornbeast(p.x + 300, 693);
  var b = Entities.hornbeast(p.x + 360, 693);
  var far = Entities.hornbeast(p.x + 900, 693);
  game.entities.push(a); game.entities.push(b); game.entities.push(far);
  var kc0 = game.killCount;
  // 原子弹直接丢到 a 头上
  game.entities.push(Entities.atombomb(a.x + 10, a.y + 5, 1));
  game.step(1 / 60);
  assert.ok(findEntity('explosion'), '命中后应生成 explosion 爆炸');
  assert.strictEqual(a.alive, false, '范围内的 a 应被炸死');
  assert.strictEqual(b.alive, false, '范围内的 b 应被炸死');
  assert.strictEqual(far.alive, true, '范围外的 far 应活着');
  assert.strictEqual(game.killCount, kc0 + 2, '炸死长角兽也应计数');
  // 爆炸约 0.5s 后消失
  stepFrames(40);
  assert.ok(!findEntity('explosion'), '爆炸应在大约 0.5 秒后消失');
});

test('原子弹落地也会炸开；爆炸不伤玩家自己', function () {
  game.debugGotoStage(8);
  settle();
  var p = game.player;
  p.invincible = 0;
  var h0 = p.hearts;
  // 把原子弹轻轻丢在脚边
  game.entities.push(Entities.atombomb(p.x + 30, p.y + 20, 1));
  stepFrames(90);   // 落地爆炸 + 炸完
  assert.ok(!findEntity('atombomb'), '原子弹落地后应炸掉');
  assert.strictEqual(p.hearts, h0, '自己的爆炸不应伤到自己');
});

test('氢弹命中大蜘蛛兽造成 25 点 AoE 伤害', function () {
  game.debugGotoStage(10);
  var boss = findEntity('spiderboss');
  assert.ok(boss, '第 4 幕应有大蜘蛛兽');
  assert.strictEqual(boss.hp, 60);
  game.entities.push(Entities.hydrogenbomb(boss.x + 90, boss.y + 60, 1));
  game.step(1 / 60);
  assert.ok(findEntity('explosion'), '氢弹命中应生成超大爆炸');
  assert.strictEqual(boss.hp, 60 - 25, '氢弹应对 Boss 造成 25 点伤害');
});

// ===== Boss：魔鬼兽 / 大蜘蛛兽 / 大螃蟹兽 / 中级蜘蛛兽 =====

test('魔鬼兽会吐火焰弹、会预警俯冲砸地', function () {
  game.debugGotoStage(9);
  settle();
  var boss = findEntity('devilbeast');
  var p = game.player;
  p.x = boss.x - 400; p.y = 630; p.vx = 0; p.vy = 0;
  // 吐火焰弹
  boss.fireT = 0.01;
  stepFrames(3);
  assert.ok(findEntity('devilfire'), '魔鬼兽应吐出火焰弹（devilfire 敌方投射物）');
  // 俯冲：先进入预警 windupT
  boss.diveT = 0.01;
  stepFrames(3);
  assert.ok(boss.windupT > 0 || boss.diving, '俯冲前应有预警/进入俯冲');
  var maxBottom = -1e9;
  for (var dk = 0; dk < 120; dk++) { game.step(1 / 60); if (boss.alive) maxBottom = Math.max(maxBottom, boss.y + boss.h); }
  assert.strictEqual(boss.diving, false, '俯冲落地后应回到悬浮');
  assert.ok(maxBottom > 688, '俯冲过程中应砸到接近地面（落点 bottom≈693）');
});

test('大蜘蛛兽会吐蛛丝球、会预警扑击', function () {
  game.debugGotoStage(10);
  settle();
  var boss = findEntity('spiderboss');
  var p = game.player;
  p.x = boss.x - 400; p.y = 630; p.vx = 0; p.vy = 0;
  boss.spitT = 0.01;
  stepFrames(3);
  assert.ok(findEntity('webball'), '大蜘蛛兽应吐出蛛丝球');
  boss.pounceT = 0.01;
  stepFrames(3);
  assert.ok(boss.windupT > 0 || boss.pouncing, '扑击前应有预警/进入扑击');
  stepFrames(120);
  assert.strictEqual(boss.pouncing, false, '扑击落地后应回到地面');
  assert.ok(Math.abs((boss.y + boss.h) - 693) < 1, '落地后应贴回地面');
});

test('蛛丝球碰到玩家扣 1 心；蛛丝球可被武器打掉', function () {
  game.debugGotoStage(10);
  settle();
  var p = game.player;
  var h0 = p.hearts;
  game.entities.push(Entities.webball(p.x, p.y + 10, 1));
  game.step(1 / 60);
  assert.strictEqual(p.hearts, h0 - 1, '被蛛丝球打到应扣 1 心');
  // 武器打掉蛛丝球
  game.hasWeapons = true; game.player.hasWeapons = true;
  var wb = Entities.webball(p.x + 300, p.y, -1);
  game.entities.push(wb);
  game.entities.push(Entities.bullet(wb.x, wb.y + 8, 1));
  game.step(1 / 60);
  assert.strictEqual(wb.alive, false, '子弹应能打掉蛛丝球');
});

test('大螃蟹兽会举巨钳砸地震出震荡波、会扔泡泡', function () {
  game.debugGotoStage(11);
  settle();
  var boss = findEntity('crabbeast');
  var p = game.player;
  p.x = boss.x - 300; p.y = 630; p.vx = 0; p.vy = 0; p.invincible = 0;
  // 巨钳砸地（预警后发动，贴地两道震荡波）
  boss.smashT = 0.01;
  stepFrames(40);
  assert.ok(countType('timeshock') >= 1, '大螃蟹兽巨钳砸地应放出震荡波');
  // 扔泡泡
  boss.bubbleT = 0.01;
  stepFrames(3);
  assert.ok(findEntity('webball'), '大螃蟹兽应扔出泡泡（webball）');
});

test('魔鬼兽的火焰弹碰到玩家扣 1 心', function () {
  game.debugGotoStage(9);
  settle();
  var p = game.player;
  p.invincible = 0;
  var h0 = p.hearts;
  game.entities.push(Entities.devilfire(p.x, p.y + 10, 1));
  game.step(1 / 60);
  assert.strictEqual(p.hearts, h0 - 1, '被魔鬼兽火焰弹打到应扣 1 心');
});

test('中级蜘蛛兽（骷髅头）会吐骷髅弹、会预警扑击', function () {
  game.debugGotoStage(12);
  settle();
  var boss = findEntity('midspider');
  var p = game.player;
  p.x = boss.x - 400; p.y = 630; p.vx = 0; p.vy = 0;
  boss.spitT = 0.01;
  stepFrames(3);
  assert.ok(findEntity('webball'), '中级蜘蛛兽应吐出骷髅弹（webball）');
  boss.pounceT = 0.01;
  stepFrames(3);
  assert.ok(boss.windupT > 0 || boss.pouncing, '扑击前应有预警/进入扑击');
  stepFrames(120);
  assert.strictEqual(boss.pouncing, false, '扑击落地后应回到地面');
  assert.ok(Math.abs((boss.y + boss.h) - 693) < 1, '落地后应贴回地面');
});

// ===== 最终 Boss：巨型时间吞噬者（光头强巨化）=====

test('巨型时间吞噬者会扔电锯、放电锯气浪、瞬移', function () {
  game.debugGotoStage(13);
  settle();
  var boss = findEntity('gianttimedevourer');
  assert.ok(boss, '第 7 幕应有巨型时间吞噬者');
  var p = game.player;
  p.x = boss.x - 400; p.y = 630; p.vx = 0; p.vy = 0;
  // 扔电锯
  boss.axeT = 0.01;
  stepFrames(3);
  assert.ok(findEntity('axe'), '光头强应扔出电锯');
  // 电锯气浪
  boss.shockT = 0.01;
  stepFrames(3);
  assert.ok(countType('timeshock') >= 1, '光头强应放出电锯气浪');
  // 瞬移
  var x0 = boss.x;
  boss.blinkT = 0.01;
  stepFrames(2);
  assert.ok(boss.blinkOut > 0 || boss.blinkIn > 0, '瞬移应先淡出');
  stepFrames(40);
  assert.ok(boss.blinkIn > 0 || boss.x !== x0, '瞬移后应换了位置或正在淡入');
});

test('电锯/电锯气浪碰到玩家扣心；冲击波跳起能躲', function () {
  game.debugGotoStage(13);
  settle();
  var p = game.player;
  var h0 = p.hearts;
  game.entities.push(Entities.axe(p.x, p.y + 10, 1));
  game.step(1 / 60);
  assert.strictEqual(p.hearts, h0 - 1, '被电锯砍到应扣 1 心');
  // 冲击波：站着中招
  game.retry();
  settle();
  p = game.player;
  game.entities.push(Entities.timeshock(p.x - 40, 693, 1));
  game.step(1 / 60);
  assert.strictEqual(p.hearts, 2, '站地上被电锯气浪扫到应扣 1 心');
  // 冲击波：跳在空中躲过
  game.retry();
  settle();
  p = game.player;
  p.y = 693 - p.h - 80; p.vy = -2; p.onGround = false;
  game.entities.push(Entities.timeshock(p.x, 693, 1));
  stepFrames(2);
  assert.strictEqual(p.hearts, 3, '跳在空中应躲过电锯气浪');
});

test('巨型时间吞噬者血量过半进入第二阶段（生气）：速度翻倍、横幅触发、变身停顿', function () {
  game.debugGotoStage(13);
  settle();
  var boss = findEntity('gianttimedevourer');
  assert.strictEqual(boss.phase, 1, '初始应为第一阶段');
  // 先削到半血以上（48 点）：仍不到一半，不该进二阶段
  game._damageBoss(boss, boss.maxHp * 0.3);
  assert.strictEqual(boss.phase, 1, '还差一点，不到一半不该进二阶段');
  // 再补一刀越过半血（35 点）：应进入第二阶段
  game._damageBoss(boss, boss.maxHp * 0.25 + 1);
  assert.strictEqual(boss.phase, 2, '血量过半应进入第二阶段');
  assert.ok(boss.transitionT > 0, '二阶段开始应有变身停顿 transitionT');
  assert.ok(game.phaseBannerT > 0, '应触发「光头强生气了」横幅');
  // 变身结束后速度应翻倍（对比一阶段基准 0.95）
  boss.transitionT = 0;
  var x0 = boss.x, p = game.player; p.x = boss.x - 200; p.vx = 0; p.vy = 0;
  stepFrames(20);
  var movedP2 = Math.abs(boss.x - x0);
  game.retry();
  settle();
  var b1 = findEntity('gianttimedevourer');
  var x1 = b1.x; p = game.player; p.x = b1.x - 200; p.vx = 0; p.vy = 0;
  stepFrames(20);
  var movedP1 = Math.abs(b1.x - x1);
  assert.ok(movedP2 > movedP1 * 1.5, '第二阶段移动速度应明显快于一阶段');
});

test('第一阶段不能召唤队友；第二阶段可召唤，最多 2 名（飞飞、童童），且会朝 Boss 射击', function () {
  game.debugGotoStage(13);
  settle();
  var boss = findEntity('gianttimedevourer');
  // 一阶段：按 B 应被拒绝（提示），且场上无队友
  Input.pressKey('KeyB'); game.step(1 / 60); Input.releaseKey('KeyB');
  assert.strictEqual(countType('ally'), 0, '一阶段按 B 不应召唤出队友');
  assert.ok(game.summonMsgT > 0, '一阶段应给出「先打到生气」的提示');
  // 推进到二阶段
  game._damageBoss(boss, boss.hp);
  boss.alive = false; boss.hp = 0;  // 不影响召唤逻辑测试：重置回满血便于连续召唤
  game.retry();
  settle();
  boss = findEntity('gianttimedevourer');
  game._damageBoss(boss, boss.maxHp * 0.6);   // 触发二阶段
  boss.transitionT = 0;
  assert.strictEqual(boss.phase, 2, '已进入二阶段');
  // 连续按 B 召唤 2 名（每次召唤后跳过冷却）
  for (var n = 1; n <= 2; n++) {
    Input.pressKey('KeyB'); game.step(1 / 60); Input.releaseKey('KeyB');
    game.summonCd = 0;   // 跳过冷却，便于测试连召
    stepFrames(2);
    assert.strictEqual(countType('ally'), n, '第 ' + n + ' 次按 B 应有 ' + n + ' 名队友');
  }
  // 第 3 次应被拒（满员 2 名）
  Input.pressKey('KeyB'); game.step(1 / 60); Input.releaseKey('KeyB');
  assert.strictEqual(countType('ally'), 2, '不能超过 2 名队友');
  // 把光头强拉到队友身边，确保队友会朝它射击
  boss.x1 = -1e9; boss.x2 = 1e9;
  boss.x = game.player.x + 150; boss.y = game.player.y;
  boss.blinkT = 999; boss.axeT = 999; boss.shockT = 999; boss.dashCd = 999;
  var hpBefore = boss.hp;
  stepFrames(180);
  // 队友子弹会直接命中近处的光头强并被消耗，所以不数"在场子弹"，
  // 而是断言光头强被队友打掉了血（验证队友确实在持续射击）
  assert.ok(boss.hp < hpBefore, '队友应持续朝光头强射击并造成伤害');
  game.retry();
});

test('宇航员队友会被巨型时间吞噬者的攻击打到、扣心，倒下后消失', function () {
  game.debugGotoStage(13);
  settle();
  var boss = findEntity('gianttimedevourer');
  game._damageBoss(boss, boss.maxHp * 0.6);
  boss.transitionT = 0;
  Input.pressKey('KeyB'); game.step(1 / 60); Input.releaseKey('KeyB');
  assert.strictEqual(countType('ally'), 1, '应召唤出 1 名队友');
  var al = findEntity('ally');
  var h0 = al.hearts;
  // 解除 Boss 活动范围钳制，否则贴脸坐标会被弹回远处而不重叠
  boss.x1 = -1e9; boss.x2 = 1e9;
  // 用光头强本体的命中盒砸队友
  boss.x = al.x - 10; boss.y = al.y;
  game.step(1 / 60);
  assert.strictEqual(al.hearts, h0 - 1, '被光头强撞到应扣 1 心');
  // 反复撞击打光 3 颗心 → 倒下（alive=false）
  for (var k = 0; k < 10 && al.alive; k++) {
    al.invincible = 0;
    boss.x = al.x - 10; boss.y = al.y;
    game.step(1 / 60);
  }
  assert.strictEqual(al.alive, false, '队友心扣光应倒下');
  // 死亡动画放完后应从场上移除（deadT 推进）
  stepFrames(60);
  assert.strictEqual(countType('ally'), 0, '倒下的队友应从场上消失（可被再次召唤补位）');
  game.retry();
});

test('大蜘蛛兽血量跨死亡持久化；被打死后胜利小节并推进到第 5 幕', function () {
  game.debugGotoStage(10);
  var boss = findEntity('spiderboss');
  assert.strictEqual(boss.hp, 60, '首次进关满血 60');
  game._damageBoss(boss, 25);
  assert.strictEqual(boss.hp, 35);
  assert.strictEqual(game.bossHp[10], 35, '应记住残血');
  // 死亡重来：接着残血打（不惩罚小朋友）
  game.retry();
  boss = findEntity('spiderboss');
  assert.strictEqual(boss.hp, 35, '死亡重来应接着 35 点残血打');
  // debug 跳关：满血
  game.debugGotoStage(10);
  boss = findEntity('spiderboss');
  assert.strictEqual(boss.hp, 60, 'debug 跳关应满血');
  // 打死：胜利小节 → 下一幕
  var score0 = game.score;
  game._damageBoss(boss, boss.hp);
  assert.strictEqual(boss.alive, false);
  assert.strictEqual(game.bossClearName, '大蜘蛛兽');
  assert.ok(game.score - score0 >= 1000, '打死 Boss 应得 1000 分');
  assert.ok(game.bossClearT > 0, '应进入胜利小节');
  assert.strictEqual(game.stageIndex, 10, '胜利小节期间还在本幕（第 11 幕·大蜘蛛兽）');
  stepFrames(150);
  assert.strictEqual(game.stageIndex, 11, '胜利小节结束应进入第 12 幕（大螃蟹兽）');
  assert.strictEqual(game.state, 'playing');
});

test('巨型时间吞噬者血量跨死亡持久化；被打死进入返航过场 → win', function () {
  game.debugGotoStage(13);
  var boss = findEntity('gianttimedevourer');
  assert.strictEqual(boss.hp, 160, '首次进关满血 160');
  game._damageBoss(boss, 60);
  assert.strictEqual(game.bossHp[13], 100);
  game.retry();
  boss = findEntity('gianttimedevourer');
  assert.strictEqual(boss.hp, 100, '死亡重来应接着 100 点残血打');
  // 打死 → 胜利小节 → 「光头强带路去蛇山」过场 → 第 15 幕 蛇山之路
  game._damageBoss(boss, boss.hp);
  assert.strictEqual(boss.alive, false);
  assert.strictEqual(game.bossClearName, '光头强');
  stepFrames(150);   // > 2s 胜利小节
  assert.strictEqual(game.state, 'cutscene', '光头强死后应进入「带路去蛇山」过场');
  assert.strictEqual(game.cutscene.type, 'toSnakeMountain');
  stepFrames(320);   // > 5s 过场
  assert.strictEqual(game.state, 'playing', '过场结束应进入第 15 幕（蛇山之路）');
  assert.strictEqual(game.stageIndex, 14, '过场结束应进入第 15 幕（idx 14）');
});

// ===== 流程 =====

test('14 幕依序真实推进到 win（原版火星主线 + 新增月球续集）', function () {
  // 通用：把玩家放到某关终点旗，触发过关
  function reachFlag(idx, fx) {
    game.debugGotoStage(idx);
    var pp = game.player; pp.x = fx; pp.y = 620; pp.vx = 0; pp.vy = 0; pp.onGround = true;
    stepFrames(2);
  }
  // 通用：进某关、击杀 Boss、等胜利小节推进
  function killBoss(idx, type, nextIdx, nextName) {
    game.debugGotoStage(idx);
    var b = findEntity(type);
    assert.ok(b, '第 ' + (idx + 1) + ' 幕应有 ' + type);
    game._damageBoss(b, b.hp);
    stepFrames(150);
    assert.strictEqual(game.stageIndex, nextIdx, '第 ' + (idx + 1) + ' 幕 → 第 ' + (nextIdx + 1) + ' 幕（' + nextName + '）');
  }

  // ===== 第 1 幕 地球：火箭发射（真实交互）=====
  game.startNewGame();
  settle();
  var p = game.player;
  p.x = 1900; p.y = 600; p.vy = 0; p.onGround = true;
  game.pressKey('ArrowUp');
  game.step(1 / 60);
  game.releaseKey('ArrowUp');
  assert.strictEqual(game.state, 'cutscene', '按 ↑ 应进入发射过场');
  stepFrames(220);
  assert.strictEqual(game.stageIndex, 1, '应进入第 2 幕（太空·陨石风暴）');
  assert.strictEqual(game.hasWeapons, false, '发射后尚未解锁（第 4 幕登船才解锁）');

  // ===== 第 2 幕 太空·陨石风暴（flag @4050）→ 第 3 幕 =====
  reachFlag(1, 4050);
  assert.strictEqual(game.stageIndex, 2, '第 2 幕终点旗 → 第 3 幕（太空·大便兽）');

  // ===== 第 3 幕 太空·大便兽（flag @3480）→ 第 4 幕 =====
  reachFlag(2, 3480);
  assert.strictEqual(game.stageIndex, 3, '第 3 幕终点旗 → 第 4 幕（长角兽军团）');

  // ===== 第 4 幕 长角兽军团：踩够 60 只 → 飞船降落 → 登船（toMars）→ 第 5 幕 =====
  game.debugGotoStage(3);
  game.killCount = 60;
  var ship = null;
  for (var k = 0; k < 900 && !ship; k++) { game.step(1 / 60); ship = findEntity('ship'); }
  assert.ok(ship, '踩够 60 只后飞船应出现');
  for (var k2 = 0; k2 < 900 && !ship.landed; k2++) { game.step(1 / 60); }
  assert.ok(ship.landed, '飞船应降落停稳');
  var pp = game.player; pp.x = ship.x; pp.y = 600; pp.vy = 0; pp.onGround = true;
  game.pressKey('ArrowUp'); game.step(1 / 60); game.releaseKey('ArrowUp');
  assert.strictEqual(game.state, 'cutscene', '登船应触发 toMars 过场');
  stepFrames(320);
  assert.strictEqual(game.stageIndex, 4, '登船后应进入第 5 幕（火星·怪物群）');
  assert.strictEqual(game.hasWeapons, true, '登船后解锁全部武器');

  // ===== 第 5 幕 火星·怪物群（flag @4080）→ 第 6 幕 =====
  reachFlag(4, 4080);
  assert.strictEqual(game.stageIndex, 5, '第 5 幕终点旗 → 第 6 幕（火星·大蜘蛛兽）');

  // ===== 第 6 幕 火星·大蜘蛛兽（boss）→ 第 7 幕 =====
  killBoss(5, 'spiderboss', 6, '神秘城堡');

  // ===== 第 7 幕 神秘城堡：进城堡（enterCastle）→ 第 8 幕 =====
  game.debugGotoStage(6);
  var cas = findEntity('castle');
  assert.ok(cas, '第 7 幕应有城堡');
  var cp = game.player; cp.x = cas.x + cas.w / 2 - 30; cp.y = 600; cp.vy = 0; cp.onGround = true;
  game.pressKey('ArrowUp'); game.step(1 / 60); game.releaseKey('ArrowUp');
  assert.strictEqual(game.state, 'cutscene', '进城堡应触发过场');
  stepFrames(130);
  assert.strictEqual(game.stageIndex, 7, '进城堡 → 第 8 幕（城堡内·光头强）');

  // ===== 第 8 幕 城堡内·光头强（普通，中级 Boss）→ 第 9 幕 =====
  killBoss(7, 'timedevourer', 8, '月球探险');

  // ===== 第 9 幕 月球探险（flag @5240）→ 第 10 幕 =====
  reachFlag(8, 5240);
  assert.strictEqual(game.stageIndex, 9, '第 9 幕终点旗 → 第 10 幕（魔鬼兽）');

  // ===== 第 10~13 幕 新增 Boss 依次击杀 =====
  killBoss(9, 'devilbeast', 10, '大蜘蛛兽');
  killBoss(10, 'spiderboss', 11, '大螃蟹兽');
  killBoss(11, 'crabbeast', 12, '中级蜘蛛兽（骷髅头）');
  killBoss(12, 'midspider', 13, '巨型时间吞噬者（光头强）');

  // ===== 第 14 幕 巨型时间吞噬者（光头强）被打败 → 光头强带路过场 → 第 15 幕 蛇山之路 =====
  game.debugGotoStage(13);
  var gtq = findEntity('gianttimedevourer');
  assert.ok(gtq, '第 14 幕应有巨型时间吞噬者');
  game._damageBoss(gtq, gtq.hp);
  stepFrames(150);
  assert.strictEqual(game.state, 'cutscene', '光头强死后进入「带路去蛇山」过场');
  assert.strictEqual(game.cutscene.type, 'toSnakeMountain');
  stepFrames(320);
  assert.strictEqual(game.stageIndex, 14, '过场结束应进入第 15 幕（蛇山之路）');

  // ===== 第 15 幕 蛇山之路：走到终点旗 → 第 16 幕 帝王蛇怪 =====
  reachFlag(14, 4650);
  assert.strictEqual(game.stageIndex, 15, '蛇山之路终点旗 → 第 16 幕（帝王蛇怪）');

  // ===== 第 16 幕 帝王蛇怪（boss）→ 第 17 幕 三头帝王蛇 =====
  killBoss(15, 'emperorsnake', 16, '三头帝王蛇');

  // ===== 第 17 幕 三头帝王蛇（最终）→ 返航过场 → win =====
  game.debugGotoStage(16);
  var finalSnake = findEntity('threeheadsnake');
  assert.ok(finalSnake, '第 17 幕应有三头帝王蛇');
  game._damageBoss(finalSnake, finalSnake.hp);
  stepFrames(150);
  assert.strictEqual(game.state, 'cutscene', '最终 Boss 死后进入返航过场');
  assert.strictEqual(game.cutscene.type, 'return');
  stepFrames(320);
  assert.strictEqual(game.state, 'win', '返航过场结束应进入胜利');
  assert.strictEqual(game.stageIndex, 17, 'win 时 stageIndex 应为 LAST_STAGE(17)');
});

test('debugGotoStage 辅助可用（n>=LAST_STAGE 进 win）', function () {
  game.debugGotoStage(15);
  assert.strictEqual(game.stageIndex, 15);
  assert.strictEqual(game.state, 'playing');
  game.debugGotoStage(17);
  assert.strictEqual(game.state, 'win');
  assert.strictEqual(game.stageIndex, 17);
});

test('扣光心进入 gameover 且能重开', function () {
  game.debugGotoStage(8);
  assert.strictEqual(game.player.hearts, 3);
  game.hitPlayer(); game.player.invincible = 0;
  game.hitPlayer(); game.player.invincible = 0;
  game.hitPlayer();
  assert.strictEqual(game.player.hearts, 0, '三次受伤应扣光心');
  assert.strictEqual(game.state, 'gameover', '应进入 gameover');
  game.pressKey('Enter');
  game.step(1 / 60);
  game.releaseKey('Enter');
  assert.strictEqual(game.state, 'playing', '重开后应回到 playing');
  assert.strictEqual(game.player.hearts, 3, '重开后应回满心');
  assert.strictEqual(game.stageIndex, 8, '应从当前幕（第 9 幕）开头重来');
});

test('重新开始（startNewGame）会重置武器与击杀数', function () {
  game.debugGotoStage(11);
  assert.strictEqual(game.hasWeapons, true);
  game.killCount = 30;
  game.startNewGame();
  assert.strictEqual(game.hasWeapons, false, '重新开始后武器应重置');
  assert.strictEqual(game.player.hasWeapons, false);
  assert.strictEqual(game.killCount, 0, '重新开始后击杀数应重置');
  assert.strictEqual(game.stageIndex, 0);
});

// ===== 渲染冒烟：用 mock 2D 上下文跑遍所有状态，确保 draw() 不报错（守护 file:// 可玩性）=====
function makeCtx() {
  var grad = { addColorStop: function () {} };
  var ctx = {
    canvas: { width: 1440, height: 810 },
    createLinearGradient: function () { return grad; },
    createRadialGradient: function () { return grad; }
  };
  ['save', 'restore', 'fillRect', 'clearRect', 'beginPath', 'closePath',
   'moveTo', 'lineTo', 'arc', 'arcTo', 'ellipse', 'bezierCurveTo', 'quadraticCurveTo',
   'fill', 'stroke', 'translate', 'scale', 'rotate', 'fillText', 'strokeText', 'strokeRect'
  ].forEach(function (m) { ctx[m] = function () {}; });
  return ctx;
}
test('draw 在各状态下不报错（渲染冒烟）', function () {
  game.ctx = makeCtx();
  game.state = 'menu'; game.time = 1; game.draw();
  // 每一幕边跑边画（地球 / 太空 / 火星 / 城堡 / 月球主题，含全部 Boss）
  for (var st = 0; st < 14; st++) {
    game.debugGotoStage(st);
    game.pressKey('ArrowRight'); stepFrames(8); game.releaseKey('ArrowRight');
    game.pressKey('Space'); game.step(1 / 60); game.releaseKey('Space'); stepFrames(8);
    game.draw();
  }
  // 五种武器 + 爆炸 + 新实体都画一遍（已解锁的关卡）
  game.debugGotoStage(9);
  var p1 = game.player;
  ['KeyH', 'KeyJ', 'KeyK', 'KeyL', 'KeyU'].forEach(function (k) {
    game.pressKey(k); game.step(1 / 60); game.releaseKey(k);
    game.player.cd = { bullet: 0, fireball: 0, missile: 0, atombomb: 0, hydrogenbomb: 0 };
  });
  game.entities.push(Entities.house(p1.x + 400, 100));
  game.entities.push(Entities.rollbeast(p1.x + 500, 693, -1));
  game.entities.push(Entities.webball(p1.x + 200, 500, 1));
  game.entities.push(Entities.axe(p1.x + 250, 480, 1));
  game.entities.push(Entities.timeshock(p1.x + 300, 693, 1));
  game.entities.push(Entities.explosion(p1.x + 350, 600, 150));
  game.entities.push(Entities.devilfire(p1.x + 250, 460, 1));
  stepFrames(3);
  game.draw();
  // 魔鬼兽：活体（血条 + 受击闪白 + 俯冲预警）、死亡
  game.debugGotoStage(9);
  var dv = findEntity('devilbeast');
  dv.fireT = 0.01; dv.hurtT = 0.1; dv.windupT = 0.4;
  stepFrames(3); game.draw();
  game._damageBoss(dv, dv.hp); stepFrames(30); game.draw();
  // 大蜘蛛兽：活体（血条 + 受击闪白 + 扑击预警）、死亡
  game.debugGotoStage(10);
  var sp = findEntity('spiderboss');
  sp.spitT = 0.01; sp.hurtT = 0.1; sp.windupT = 0.4;
  stepFrames(3); game.draw();
  game._damageBoss(sp, sp.hp); stepFrames(30); game.draw();
  // 大螃蟹兽：活体（血条 + 巨钳砸地预警）、死亡
  game.debugGotoStage(11);
  var cb = findEntity('crabbeast');
  cb.smashT = 0.01; cb.hurtT = 0.1;
  stepFrames(3); game.draw();
  game._damageBoss(cb, cb.hp); stepFrames(30); game.draw();
  // 中级蜘蛛兽：活体（骷髅头 + 扑击预警）、死亡
  game.debugGotoStage(12);
  var ms = findEntity('midspider');
  ms.spitT = 0.01; ms.hurtT = 0.1; ms.windupT = 0.4;
  stepFrames(3); game.draw();
  game._damageBoss(ms, ms.hp); stepFrames(30); game.draw();
  // 巨型时间吞噬者（光头强巨化）：活体（血条 + 瞬移淡出）、死亡倒下
  game.debugGotoStage(13);
  var td = findEntity('gianttimedevourer');
  td.axeT = 0.01; td.hurtT = 0.1; td.blinkOut = 0.3;
  stepFrames(3); game.draw();
  td.blinkOut = 0;
  game._damageBoss(td, td.hp); stepFrames(30); game.draw();
  // 发射过场
  game.debugGotoStage(0);
  var p = game.player; p.x = 1900; p.y = 600; p.onGround = true; p.vy = 0;
  game.pressKey('ArrowUp'); game.step(1 / 60); game.releaseKey('ArrowUp');
  assert.strictEqual(game.state, 'cutscene');
  game.draw(); stepFrames(10); game.draw();
  // 返航过场（三段都画到）
  game.debugGotoStage(13);
  var td2 = findEntity('gianttimedevourer');
  game._damageBoss(td2, td2.hp);
  stepFrames(150);
  assert.strictEqual(game.state, 'cutscene');
  game.draw(); stepFrames(120); game.draw(); stepFrames(120); game.draw();
  // 胜利 / 失败 / 暂停
  game.state = 'win'; game.draw();
  game.state = 'gameover'; game.draw();
  game.debugGotoStage(8); game.paused = true; game.draw(); game.paused = false;
  game.ctx = null; // 还原，避免影响后续
});

// ===== 4. 汇总 =====
console.log('\n' + passed + ' passed, ' + failed + ' failed');
if (failed > 0) {
  console.log('SOME TESTS FAILED');
  process.exit(1);
} else {
  console.log('ALL TESTS PASSED');
  process.exit(0);
}
