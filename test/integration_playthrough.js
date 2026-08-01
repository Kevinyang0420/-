// 合并版端到端流程验证：原版火星主线(8幕) + 新增月球续集(6幕) = 14 幕全贯通
// 地球发射→太空陨石→大便兽→长角兽军团(登船)→火星怪物群→火星大蜘蛛兽→城堡→光头强(中级)
// →月球探险→魔鬼兽→大蜘蛛兽→大螃蟹兽→中级蜘蛛兽(骷髅头)→巨型时间吞噬者(最终)→胜利
var fs = require('fs'), vm = require('vm'), path = require('path');
global.window = global;
global.performance = { now: function () { return Date.now(); } };
global.document = { addEventListener: function () {}, getElementById: function () { return null; } };
var JS = path.join(process.cwd(), 'js');
['util', 'input', 'audio', 'entities', 'levels', 'render', 'game'].forEach(function (n) {
  vm.runInThisContext(fs.readFileSync(path.join(JS, n + '.js'), 'utf8'), { filename: n + '.js' });
});
var game = global.game;
var failures = 0;
function ok(cond, msg) { if (!cond) { failures++; console.log('  ✗ ' + msg); } else { console.log('  ✓ ' + msg); } }
function step(n) { for (var i = 0; i < n; i++) game.step(1 / 60); }
function find(type) { return game.entities.filter(function (e) { return e.type === type; }); }

console.log('\n[0] 第 1 幕 地球出发 → 发射火箭');
game.startNewGame();
step(20);
var p = game.player;
p.x = 1900; p.y = 600; p.vy = 0; p.onGround = true;
game.pressKey('ArrowUp'); game.step(1 / 60); game.releaseKey('ArrowUp');
ok(game.state === 'cutscene' && game.cutscene.type === 'launch', '进入发射过场');
ok(game.hasWeapons === false, '发射时尚未解锁武器');
step(220);
ok(game.stageIndex === 1 && game.state === 'playing', '过场结束进入第 2 幕（太空·陨石风暴）');

function reachFlag(idx, fx) {
  game.debugGotoStage(idx);
  var pp = game.player; pp.x = fx; pp.y = 620; pp.vx = 0; pp.vy = 0; pp.onGround = true;
  step(2);
}
console.log('\n[1-2] 太空双关：陨石风暴 / 大便兽 终点旗');
reachFlag(1, 4050); ok(game.stageIndex === 2, '第 2 幕终点旗 → 第 3 幕（大便兽）');
reachFlag(2, 3480); ok(game.stageIndex === 3, '第 3 幕终点旗 → 第 4 幕（长角兽军团）');

console.log('\n[3] 第 4 幕 长角兽军团：踩够 60 只 → 飞船降落 → 登船');
game.debugGotoStage(3);
game.player.invincible = 999; // 等待飞船期间避免被长角兽碰死
game.killCount = 60;
var ship = null;
for (var k = 0; k < 900 && !ship; k++) { game.step(1 / 60); ship = find('ship')[0]; }
ok(!!ship, '飞船出现');
for (var k2 = 0; k2 < 900 && ship && !ship.landed; k2++) { game.step(1 / 60); }
ok(ship && ship.landed, '飞船降落停稳');
p = game.player; p.x = ship.x; p.y = 600; p.vy = 0; p.onGround = true;
game.pressKey('ArrowUp'); game.step(1 / 60); game.releaseKey('ArrowUp');
ok(game.state === 'cutscene' && game.cutscene.type === 'toMars', '登船触发 toMars 过场');
step(320);
ok(game.stageIndex === 4, '登船 → 第 5 幕（火星·怪物群）');
ok(game.hasWeapons === true, '登船后解锁全部武器');

console.log('\n[4] 第 5 幕 火星·怪物群 终点旗');
reachFlag(4, 4080); ok(game.stageIndex === 5, '→ 第 6 幕（火星·大蜘蛛兽）');

console.log('\n[5] 第 6 幕 火星·大蜘蛛兽（boss）');
game.debugGotoStage(5);
var sp = find('spiderboss')[0];
ok(!!sp, '有火星大蜘蛛兽');
game._damageBoss(sp, sp.hp); step(150);
ok(game.stageIndex === 6, '→ 第 7 幕（神秘城堡）');

console.log('\n[6] 第 7 幕 神秘城堡 → 进城堡');
game.debugGotoStage(6);
var cas = find('castle')[0];
ok(!!cas, '有城堡');
p = game.player; p.x = cas.x + cas.w / 2 - 30; p.y = 600; p.vy = 0; p.onGround = true;
game.pressKey('ArrowUp'); game.step(1 / 60); game.releaseKey('ArrowUp');
ok(game.state === 'cutscene' && game.cutscene.type === 'enterCastle', '进城堡过场');
step(130);
ok(game.stageIndex === 7, '→ 第 8 幕（城堡内·光头强）');

console.log('\n[7] 第 8 幕 城堡内·光头强（普通，中级 Boss）');
game.debugGotoStage(7);
var tt = find('timedevourer')[0];
ok(!!tt, '有光头强');
game._damageBoss(tt, tt.hp); step(150);
ok(game.stageIndex === 8, '→ 第 9 幕（月球探险）');

console.log('\n[8] 第 9 幕 月球探险 终点旗');
reachFlag(8, 5240); ok(game.stageIndex === 9, '→ 第 10 幕（魔鬼兽）');

var plan = [
  { si: 9, kind: 'devilbeast', name: '魔鬼兽' },
  { si: 10, kind: 'spiderboss', name: '大蜘蛛兽（月球）' },
  { si: 11, kind: 'crabbeast', name: '大螃蟹兽' },
  { si: 12, kind: 'midspider', name: '中级蜘蛛兽（骷髅头）' },
  { si: 13, kind: 'gianttimedevourer', name: '巨型时间吞噬者（光头强）' }
];
plan.forEach(function (b, idx) {
  console.log('\n[9.' + (idx + 1) + '] 第 ' + (b.si + 1) + ' 幕 ' + b.name);
  game.debugGotoStage(b.si);
  var boss = find(b.kind)[0];
  ok(!!boss, '场景里有 ' + b.name);
  if (b.kind === 'gianttimedevourer') {
    game._damageBoss(boss, Math.ceil(boss.maxHp * 0.55));
    ok(boss.phase === 2, '巨型时间吞噬者血量过半进入第二阶段（生气）');
  }
  game._damageBoss(boss, boss.hp);
  ok(boss.alive === false, b.name + ' 被击杀');
  step(150);
  if (b.si < 13) ok(game.stageIndex === b.si + 1, b.name + ' 清场后进入下一幕');
  else {
    ok(game.state === 'cutscene' && game.cutscene.type === 'return', '最终 Boss 清场进入返航过场');
    step(320);
    ok(game.state === 'win', '游戏通关（win 状态）');
  }
});

console.log('\n========================================');
if (failures === 0) { console.log('合并版端到端流程全部通过 ✓'); process.exit(0); }
else { console.log('有 ' + failures + ' 项失败 ✗'); process.exit(1); }
