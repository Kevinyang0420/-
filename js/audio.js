// audio.js - WebAudio 合成音效（无外部音频文件，全部代码生成）
var Sfx = {
  ctx: null,
  enabled: true,
  _started: false,

  init: function () {
    if (this._started) return;
    this._started = true;
    try {
      var AC = (typeof window !== 'undefined') && (window.AudioContext || window.webkitAudioContext);
      if (AC) this.ctx = new AC();
    } catch (e) { this.ctx = null; }
    this._installUnlock();
  },

  // iOS/移动端：AudioContext 必须由用户手势激活后才能发声，首次交互时解锁
  _installUnlock: function () {
    var self = this;
    var unlock = function () {
      self.resume();
      self._silentUnlock();
      window.removeEventListener('touchstart', unlock);
      window.removeEventListener('click', unlock);
      window.removeEventListener('keydown', unlock);
    };
    window.addEventListener('touchstart', unlock, false);
    window.addEventListener('click', unlock, false);
    window.addEventListener('keydown', unlock, false);
  },

  // 在用户手势回调内播放一段极短静音，强制 iOS 真正解锁音频
  _silentUnlock: function () {
    if (!this.ctx) return;
    try {
      var b = this.ctx.createBuffer(1, 1, this.ctx.sampleRate);
      var src = this.ctx.createBufferSource();
      src.buffer = b;
      src.connect(this.ctx.destination);
      src.start(0);
    } catch (e) {}
  },

  // 用户首次交互后恢复（浏览器自动暂停策略）
  resume: function () {
    if (this.ctx && this.ctx.state === 'suspended') {
      try { this.ctx.resume(); } catch (e) {}
    }
  },

  setEnabled: function (on) { this.enabled = on; },

  // 单音合成：频率、时长、波形、音量、滑落目标频率
  _tone: function (freq, dur, type, vol, slideTo) {
    if (!this.ctx || !this.enabled) return;
    var t = this.ctx.currentTime;
    var osc = this.ctx.createOscillator();
    var gain = this.ctx.createGain();
    osc.type = type || 'square';
    osc.frequency.setValueAtTime(freq, t);
    if (slideTo) {
      osc.frequency.exponentialRampToValueAtTime(Math.max(1, slideTo), t + dur);
    }
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(vol || 0.2, t + 0.012);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.start(t);
    osc.stop(t + dur + 0.03);
  },

  // 噪声爆裂（用于爆炸/着陆尘土）
  _noise: function (dur, vol) {
    if (!this.ctx || !this.enabled) return;
    var t = this.ctx.currentTime;
    var n = Math.floor(this.ctx.sampleRate * dur);
    var buf = this.ctx.createBuffer(1, n, this.ctx.sampleRate);
    var data = buf.getChannelData(0);
    for (var i = 0; i < n; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / n);
    var src = this.ctx.createBufferSource();
    src.buffer = buf;
    var gain = this.ctx.createGain();
    gain.gain.setValueAtTime(vol || 0.15, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(gain);
    gain.connect(this.ctx.destination);
    src.start(t);
    src.stop(t + dur);
  },

  jump: function () { this._tone(420, 0.18, 'square', 0.16, 760); },
  land: function () { this._tone(240, 0.06, 'triangle', 0.10); this._noise(0.05, 0.05); },
  hurt: function () { this._tone(320, 0.22, 'sawtooth', 0.18, 110); this._noise(0.12, 0.08); },
  stomp: function () { this._tone(200, 0.10, 'square', 0.18, 70); this._tone(500, 0.08, 'square', 0.10); },
  launch: function () {
    this._tone(110, 1.0, 'sawtooth', 0.22, 520);
    this._noise(0.9, 0.18);
    var self = this;
    setTimeout(function () { self._tone(80, 0.8, 'square', 0.14, 360); }, 220);
  },
  returnFly: function () {
    this._tone(220, 1.2, 'sine', 0.12, 660);
    var self = this;
    setTimeout(function () { self._tone(440, 0.6, 'triangle', 0.12, 880); }, 600);
  },
  win: function () {
    var notes = [523, 659, 784, 1046];
    var self = this;
    notes.forEach(function (f, i) {
      setTimeout(function () { self._tone(f, 0.26, 'square', 0.18); }, i * 180);
    });
  },
  gameover: function () {
    var notes = [400, 330, 262, 196];
    var self = this;
    notes.forEach(function (f, i) {
      setTimeout(function () { self._tone(f, 0.30, 'sawtooth', 0.16); }, i * 200);
    });
  },

  // 鼻涕兽吐鼻涕球：「啵」
  snotSpit: function () { this._tone(520, 0.10, 'sine', 0.20, 140); },
  // 蜘蛛兽吐蛛丝球：更低的「噗」
  webSpit: function () { this._tone(300, 0.14, 'sine', 0.18, 90); this._noise(0.08, 0.06); },
  // 鼻涕球落地 / 踩进黏液：「吧唧」
  squelch: function () { this._tone(180, 0.16, 'sine', 0.16, 70); this._noise(0.08, 0.05); },
  // 臭袜子兽放臭气：「噗」
  stinkPuff: function () { this._noise(0.22, 0.13); this._tone(130, 0.20, 'sawtooth', 0.09, 55); },
  // 被臭气熏晕
  dizzy: function () { this._tone(600, 0.12, 'sine', 0.14, 300); this._tone(300, 0.16, 'sine', 0.12, 520); },
  // 房子砸到地面：「哐当」
  houseCrash: function () { this._tone(140, 0.25, 'square', 0.20, 60); this._noise(0.22, 0.16); },

  // 子弹发射：「biu」
  shoot: function () { this._tone(880, 0.09, 'square', 0.14, 320); },
  // 火球发射：「呼」
  fireball: function () { this._noise(0.28, 0.14); this._tone(240, 0.26, 'sawtooth', 0.10, 90); },
  // 大导弹发射：「嗖——」
  missile: function () { this._noise(0.35, 0.16); this._tone(180, 0.35, 'sawtooth', 0.12, 720); },
  // 原子弹/氢弹出手：「丢」
  bombThrow: function () { this._tone(520, 0.12, 'triangle', 0.14, 220); },
  // 爆炸：huge=true 是氢弹（更大更深）
  explosion: function (huge) {
    if (huge) {
      this._tone(48, 0.9, 'sawtooth', 0.30, 22);
      this._noise(0.8, 0.26);
      var self = this;
      setTimeout(function () { self._tone(38, 0.6, 'sine', 0.24, 20); }, 180);
      setTimeout(function () { self._noise(0.4, 0.16); }, 350);
    } else {
      this._tone(70, 0.55, 'sawtooth', 0.26, 30);
      this._noise(0.5, 0.22);
    }
  },
  // 光头强扔电锯：「呼」
  axeThrow: function () { this._noise(0.18, 0.12); this._tone(360, 0.18, 'triangle', 0.10, 140); },
  // 电锯气浪：「咚」
  shockCast: function () { this._tone(95, 0.32, 'sine', 0.28, 38); this._noise(0.18, 0.14); },
  // 光头强一溜烟窜位：「嗖」
  timeBlink: function () {
    this._tone(1568, 0.10, 'sine', 0.12, 880);
    var self = this;
    setTimeout(function () { self._tone(2093, 0.14, 'sine', 0.10, 1200); }, 70);
  },
  // 飞船降落：「咚 + 叮」
  shipLand: function () {
    this._tone(120, 0.3, 'sine', 0.22, 50);
    this._noise(0.2, 0.14);
    var self = this;
    setTimeout(function () { self._tone(880, 0.2, 'sine', 0.12); }, 200);
  },
  // 走进城堡：低沉钟声
  castleEnter: function () {
    this._tone(196, 0.8, 'sine', 0.20);
    this._tone(98, 1.0, 'sine', 0.16);
  },
  // 登船解锁全部必杀技：上扬琶音
  unlockAll: function () {
    var notes = [523, 659, 784, 1046, 1318];
    var self = this;
    notes.forEach(function (f, i) {
      setTimeout(function () { self._tone(f, 0.22, 'square', 0.14); }, i * 120);
    });
  },
  // Boss 受击：「砰」
  bossHit: function () { this._tone(180, 0.10, 'square', 0.18, 90); this._noise(0.06, 0.08); },
  // Boss 死亡：「轰隆隆」
  bossDie: function () {
    this._tone(60, 0.7, 'sawtooth', 0.26, 28);
    this._noise(0.6, 0.20);
    var self = this;
    setTimeout(function () { self._tone(45, 0.5, 'sine', 0.22, 24); }, 220);
    setTimeout(function () { self._noise(0.35, 0.14); }, 380);
  },
  // 光头强生气（进入第二阶段）：低沉咆哮
  angry: function () {
    this._tone(150, 0.5, 'sawtooth', 0.24, 70);
    this._noise(0.4, 0.16);
    var self = this;
    setTimeout(function () { self._tone(90, 0.45, 'square', 0.20, 48); }, 170);
  },
  // 召唤宇航员队友：「叮咚」
  summon: function () {
    this._tone(880, 0.12, 'sine', 0.16, 1320);
    var self = this;
    setTimeout(function () { self._tone(1175, 0.16, 'sine', 0.16, 1568); }, 90);
  },
  // 队友开枪：「啾」
  allyShoot: function () { this._tone(1040, 0.07, 'square', 0.10, 360); }
};
