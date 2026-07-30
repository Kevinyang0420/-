// input.js - 键盘输入 + 编程输入接口（pressKey/releaseKey 与真实键盘共用同一状态）
var Input = {
  down: {},      // 当前按住的按键 code -> true
  pressed: {},   // 本帧「刚按下」的边沿标记
  // 按键 code -> 触发的动作列表（一个键可触发多个动作）
  // 五种必杀技：H 子弹 / J 火球 / K 大导弹 / L 原子弹 / U 氢弹（第 4 幕登船后解锁）
  _map: {
    ArrowLeft: ['left'], KeyA: ['left'],
    ArrowRight: ['right'], KeyD: ['right'],
    ArrowUp: ['jump', 'interact'], KeyW: ['jump'], Space: ['jump'],
    KeyP: ['pause'], Escape: ['pause'],
    KeyM: ['mute'],
    KeyH: ['bullet'], KeyJ: ['fireball'], KeyK: ['missile'],
    KeyL: ['atombomb'], KeyU: ['hydrogenbomb'],
    KeyB: ['summon'],                     // 最终决战第二阶段：召唤宇航员队友
    Enter: ['start']
  },
  _bound: false,

  init: function (target) {
    if (this._bound) return;
    var self = this;
    this._onKeyDown = function (e) {
      // 忽略浏览器自动重复的 keydown，只保留首按边沿
      if (e.repeat) { self.down[e.code] = true; return; }
      self.pressKey(e.code);
      if (e.preventDefault && ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Space'].indexOf(e.code) >= 0) {
        e.preventDefault();
      }
    };
    this._onKeyUp = function (e) { self.releaseKey(e.code); };
    var t = target || (typeof window !== 'undefined' ? window : null);
    if (t && t.addEventListener) {
      t.addEventListener('keydown', this._onKeyDown);
      t.addEventListener('keyup', this._onKeyUp);
      this._bound = true;
    }
  },

  // 编程输入接口（测试与触摸按钮共用）
  pressKey: function (code) {
    if (!this.down[code]) this.pressed[code] = true;
    this.down[code] = true;
  },
  releaseKey: function (code) {
    this.down[code] = false;
  },

  // 原始按键查询
  isDown: function (code) { return !!this.down[code]; },
  justPressed: function (code) { return !!this.pressed[code]; },

  // 按动作查询（连续按住）
  action: function (name) {
    for (var code in this._map) {
      if (this.down[code] && this._map[code].indexOf(name) >= 0) return true;
    }
    return false;
  },
  // 按动作查询（本帧刚按下，边沿触发）
  actionPressed: function (name) {
    for (var code in this._map) {
      if (this.pressed[code] && this._map[code].indexOf(name) >= 0) return true;
    }
    return false;
  },

  // 每帧末清除「刚按下」标记
  endFrame: function () { this.pressed = {}; },
  reset: function () { this.down = {}; this.pressed = {}; }
};
