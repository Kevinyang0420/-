// test/bot_sanity.js - 难度健全性检查（不进交付验收，手动跑的辅助脚本）
// 模拟一个「只会按住右 + 看到威胁就跳」的小朋友，验证每幕都能在合理次数内通过。
var fs = require('fs');
var path = require('path');
var vm = require('vm');

global.window = global;
global.performance = global.performance || { now: function () { return Date.now(); } };
global.document = { addEventListener: function () {}, getElementById: function () { return null; } };
global.requestAnimationFrame = global.requestAnimationFrame || function (cb) { return setTimeout(function () { cb(0); }, 16); };

var JS_DIR = path.join(__dirname, '..', 'js');
['util', 'input', 'audio', 'entities', 'levels', 'render', 'game'].forEach(function (name) {
  vm.runInThisContext(fs.readFileSync(path.join(JS_DIR, name + '.js'), 'utf8'), { filename: name + '.js' });
});
var game = global.game;
var Input = global.Input;

var THREATS = { snowball: 180, poopbeast: 150, snotbeast: 150, sockbeast: 150,
                snotball: 180, slime: 130, shockwave: 260, devilbeast: 220, stink: 100 };

function isThreat(e) { return THREATS[e.type] && e.alive; }

// Boss 幕专用打法：面朝 Boss 保持中距离，连点 J/K 射击；蝙蝠逼近或 Boss 俯冲到脸上就跳
function bossBotFrame(p) {
  var i, e;
  var boss = null;
  for (i = 0; i < game.entities.length; i++) {
    e = game.entities[i];
    if (e.type === 'vampirebeast' && e.alive) boss = e;
  }
  if (boss) {
    var bcx = boss.x + boss.w / 2;
    var pcx = p.x + p.w / 2;
    var dist = Math.abs(bcx - pcx);
    // 站位：太远就朝 Boss 走、太近就退开（facing 随移动方向，子弹自然朝 Boss 飞）
    var want = 0;
    if (dist > 260) want = bcx < pcx ? -1 : 1;
    else if (dist < 140) want = bcx < pcx ? 1 : -1;
    if (want < 0) { game.releaseKey('ArrowRight'); game.pressKey('ArrowLeft'); }
    else if (want > 0) { game.releaseKey('ArrowLeft'); game.pressKey('ArrowRight'); }
    else {
      // 站桩时也要面朝 Boss，不然子弹会朝背后飞
      game.releaseKey('ArrowLeft'); game.releaseKey('ArrowRight');
      p.facing = bcx < pcx ? -1 : 1;
    }
    // 连点 J / K（每帧先松再按 = 制造按键边沿）
    game.releaseKey('KeyJ'); game.pressKey('KeyJ');
    game.releaseKey('KeyK'); game.pressKey('KeyK');
  }
  // 跳跃躲避：逼近的蝙蝠（不管从哪边来）/ 俯冲或低飞压到脸上的 Boss
  if (Input.isDown('Space')) {
    if (p.vy > -2 || this._jumpHold-- <= 0) game.releaseKey('Space');
  } else if (p.onGround) {
    var jump = false;
    for (i = 0; i < game.entities.length; i++) {
      e = game.entities[i];
      if (e.type === 'bat' && e.alive && !e.drain &&
          e.x + e.w > p.x - 110 && e.x < p.x + p.w + 110 &&
          e.y + e.h > p.y + 10 && e.y < p.y + p.h + 60) { jump = true; break; }
      if (e.type === 'vampirebeast' && e.alive &&
          (e.diving || e.y + e.h > p.y + 40) &&
          e.x + e.w > p.x - 30 && e.x < p.x + p.w + 130 &&
          e.y + e.h > p.y + 30) { jump = true; break; }
    }
    if (jump) { game.pressKey('Space'); this._jumpHold = 45; }
  }
}

function botFrame(idx) {
  var p = game.player;
  if (!p) return;
  var s = global.STAGES[idx];
  if (s && s.goal === 'boss') { bossBotFrame(p); return; }
  game.pressKey('ArrowRight');
  // 扫描正前方威胁
  if (Input.isDown('Space')) {
    // 按住跳到接近最高点再松手（满跳，模拟小朋友看到威胁就用力跳）
    if (p.vy > -2 || this._jumpHold-- <= 0) game.releaseKey('Space');
  } else if (p.onGround) {
    var jump = false;
    for (var i = 0; i < game.entities.length; i++) {
      var e = game.entities[i];
      if (!isThreat(e)) continue;
      var ahead = THREATS[e.type];
      var eh = e.h || (e.r ? e.r * 2 : 0);
      if (e.x + (e.w || 0) > p.x - 10 && e.x < p.x + p.w + ahead && e.y + eh > p.y + 20) { jump = true; break; }
    }
    if (jump) { game.pressKey('Space'); this._jumpHold = 45; }
  }
  // 终点交互（只在接近目标时才按 ↑，保证有按键边沿）
  var s = global.STAGES[idx];
  var nearGoal = false;
  if (s && (s.goal === 'rocket' || s.goal === 'ship')) {
    for (var g = 0; g < game.entities.length; g++) {
      var ge = game.entities[g];
      if ((ge.type === 'rocket' || ge.type === 'ship') && !ge.used && Math.abs(ge.x - p.x) < 260) { nearGoal = true; break; }
    }
  }
  // 每帧松开再按 = 模拟小朋友连点 ↑，保证有按键边沿
  if (nearGoal) { game.releaseKey('ArrowUp'); game.pressKey('ArrowUp'); }
  else if (Input.isDown('ArrowUp')) game.releaseKey('ArrowUp');
}

function playStage(idx) {
  game.debugGotoStage(idx);
  // Boss 幕需要射击技能：模拟一个已经过山洞、捡到子弹和火球的玩家
  if (global.STAGES[idx].goal === 'boss') {
    game.hasGun = true; game.hasFire = true;
    game.player.hasGun = true; game.player.hasFire = true;
  }
  var attempts = 1, frames = 0;
  var deaths = [], lastHearts = 3;
  while (frames < 60 * 120) {
    frames++;
    if (game.state === 'gameover') {
      attempts++;
      if (attempts > 12) return { ok: false, attempts: attempts, why: 'too many deaths' };
      game.retry();
      Input.reset();
    }
    if (game.player && game.player.hearts < lastHearts) {
      deaths.push(Math.round(game.player.x));
      lastHearts = game.player.hearts;
    }
    if (game.stageIndex !== idx || game.state === 'win' || game.state === 'cutscene') {
      // 过关（进飞船/火箭的过场也算）
      return { ok: true, attempts: attempts, secs: (frames / 60).toFixed(1), deaths: deaths };
    }
    if (game.state === 'playing') botFrame(idx);
    game.step(1 / 60);
  }
  return { ok: false, attempts: attempts, why: 'timeout', deaths: deaths };
}

var allOk = true;
for (var st = 0; st <= 8; st++) {
  var r = playStage(st);
  if (!r.ok) allOk = false;
  console.log('第 ' + (st + 1) + ' 幕 [' + global.STAGES[st].name + '] : ' +
    (r.ok ? 'PASS' : 'FAIL(' + r.why + ')') +
    '  尝试 ' + r.attempts + ' 次' + (r.secs ? '，用时 ' + r.secs + 's' : '') +
    (r.deaths && r.deaths.length ? '  受伤位置x=' + r.deaths.join(',') : ''));
  Input.reset();
}
console.log(allOk ? 'BOT: 全部 9 个可玩幕都能在合理次数内通过' : 'BOT: 有幕太难了，需要调难度');
process.exit(allOk ? 0 : 1);
