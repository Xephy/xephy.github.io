// ナビ (/reborn/navi/)。道は bin/navi-build が探して assets/navi/<進み具合>.json に
// 書き出してある。ここでは選ばれた組み合わせの道を読み出して、地図の上に引く。
//
// 地図は 1マス 16px の画像 (maps/m<地図>.webp) に、その時点で出ている人物の重ね絵
// (<進み具合>/m<地図>.webp) を載せる。道は地図と同じ座標 (マス) の SVG で重ねる。
(function () {
  'use strict';
  var root = document.getElementById('navi');
  if (!root) return;

  var TILE = 16;
  var BASE = root.getAttribute('data-base');
  var $ = function (id) { return document.getElementById(id); };
  var DEG = { '北': 0, '東': 90, '南': 180, '西': 270 };
  var cache = {};
  var data = null, route = null, cur = 0, shownMap = null;
  var view = { x: 0, y: 0, s: 1 };

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  // ---------------------------------------------------------------- 読み込み

  function load(key) {
    if (cache[key]) return Promise.resolve(cache[key]);
    return fetch(BASE + key + '.json').then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.json();
    }).then(function (j) { cache[key] = j; return j; });
  }

  function fillPlaces() {
    var opts = data.places.map(function (p) {
      var dis = p.at ? '' : ' disabled';
      var note = p.at ? '' : '（この時点では案内できません）';
      return '<option value="' + esc(p.id) + '"' + dis + '>' + esc(p.name + note) + '</option>';
    }).join('');
    [$('navi-from'), $('navi-to')].forEach(function (sel) {
      var keep = sel.value;
      sel.innerHTML = opts;
      sel.disabled = false;
      if (keep && data.places.some(function (p) { return p.id === keep && p.at; })) sel.value = keep;
    });
    if ($('navi-from').value === $('navi-to').value) {
      var other = data.places.filter(function (p) { return p.at && p.id !== $('navi-from').value; })[0];
      if (other) $('navi-to').value = other.id;
    }
  }

  function selectChapter(key) {
    $('navi-msg').textContent = '';
    [$('navi-from'), $('navi-to')].forEach(function (s) { s.disabled = true; });
    return load(key).then(function (j) { data = j; fillPlaces(); })
      .catch(function () { $('navi-msg').textContent = '道のデータを読み込めませんでした。'; });
  }

  // ---------------------------------------------------------------- 案内

  function placeName(id) {
    var p = data.places.filter(function (q) { return q.id === id; })[0];
    return p ? p.name : id;
  }

  function start() {
    var a = $('navi-from').value, b = $('navi-to').value;
    $('navi-msg').textContent = '';
    if (!data) return;
    if (a === b) { $('navi-msg').textContent = '出発地と目的地が同じです。'; return; }
    route = data.routes[a + '>' + b];
    if (!route) {
      var opt = $('navi-prog').selectedOptions[0];
      var fly = opt && +opt.getAttribute('data-badges') >= 13;   // そらをとぶはバッジ13個から
      $('navi-msg').textContent = 'この進み具合では、' + placeName(a) + 'から' + placeName(b) +
        'へ歩いて行ける道が見つかりませんでした。' + (fly ? 'この時点では空を飛ぶが使えます。' : '');
      return;
    }
    var names = [];
    route.steps.forEach(function (s) {
      var n = data.maps[s.map].name;
      if (names[names.length - 1] !== n) names.push(n);
    });
    $('navi-summary').hidden = false;
    $('navi-summary').innerHTML = '<div class="navi-total">' + route.total + '歩<small>出入り ' +
      route.doors + '回</small></div><div class="navi-crumbs">' + names.map(esc).join(' › ') + '</div>';
    $('navi-steps').innerHTML = route.steps.map(function (s, i) {
      var extra = s.moves && s.moves.length ? '<div class="navi-step-moves">' + s.moves.map(esc).join('・') + '</div>' : '';
      return '<li data-i="' + i + '"><span class="navi-n">' + (i + 1) + '</span><div>' +
        '<div class="navi-step-text">' + esc(s.text) + '</div>' +
        (s.dirs ? '<div class="navi-step-dirs">' + esc(s.dirs) + '</div>' : '') + extra +
        (s.walk ? '<div class="navi-step-walk">' + s.walk + '歩</div>' : '') + '</div></li>';
    }).join('');
    Array.prototype.forEach.call($('navi-steps').children, function (li) {
      li.addEventListener('click', function () { go(+li.getAttribute('data-i')); });
    });
    $('navi-hint').hidden = true;
    $('navi-stepnav').hidden = false;
    $('navi-banner').hidden = false;
    $('navi-mapname').hidden = false;
    shownMap = null;
    go(0);
    // 共有できるように、選んだものをアドレスに残す
    try {
      var q = '?p=' + encodeURIComponent($('navi-prog').value) + '&from=' + encodeURIComponent(a) +
        '&to=' + encodeURIComponent(b);
      history.replaceState(null, '', location.pathname + q + location.hash);
    } catch (e) { /* 使えない環境では残さない */ }
    if (stacked()) $('navi-map').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function stacked() {
    return getComputedStyle(root).display !== 'grid';
  }

  function firstDir(s) {
    var re = /(北|東|南|西)へ(\d+)歩/g, m, first = null;
    while ((m = re.exec(s.dirs || ''))) {
      if (!first) first = m[1];
      if (+m[2] >= 3) return m[1];
    }
    return first;
  }

  function arrow(dir, goal) {
    if (goal) {
      return '<svg class="navi-arrow" viewBox="0 0 48 48"><path d="M24 4c-8 0-14 6-14 14 0 10 14 26 14 26s14-16 14-26c0-8-6-14-14-14z" fill="#fff"/><circle cx="24" cy="18" r="5" fill="currentColor"/></svg>';
    }
    var r = DEG[dir] || 0;
    return '<svg class="navi-arrow" viewBox="0 0 48 48"><g transform="rotate(' + r + ' 24 24)"><path d="M24 5 L38 22 H29 V43 H19 V22 H10 Z" fill="#fff"/></g></svg>';
  }

  function drawMap(i) {
    var s = route.steps[i], m = data.maps[s.map];
    var W = m.w * TILE, H = m.h * TILE;
    var pl = function (pts) {
      return pts.map(function (p) { return (p[0] + 0.5) + ',' + (p[1] + 0.5); }).join(' ');
    };
    var svg = '<svg width="' + W + '" height="' + H + '" viewBox="0 0 ' + m.w + ' ' + m.h + '">';
    route.steps.forEach(function (t, j) {
      if (t.map !== s.map || t.pts.length < 2) return;
      var on = j === i;
      svg += '<polyline points="' + pl(t.pts) + '" class="navi-line-case' + (on ? ' is-on' : '') + '"/>';
      svg += '<polyline points="' + pl(t.pts) + '" class="navi-line' + (on ? ' is-on' : '') + '"/>';
    });
    var a = s.pts[0], b = s.pts[s.pts.length - 1];
    svg += '<circle cx="' + (a[0] + 0.5) + '" cy="' + (a[1] + 0.5) + '" r="' + (i === 0 ? 0.6 : 0.45) +
      '" class="' + (i === 0 ? 'navi-start' : 'navi-here') + '"/>';
    if (i === route.steps.length - 1) {
      svg += '<g transform="translate(' + (b[0] + 0.5) + ' ' + (b[1] + 0.5) + ')"><path d="M0 0c-.25-.7-1.1-1.3-1.1-2.2a1.1 1.1 0 0 1 2.2 0c0 .9-.85 1.5-1.1 2.2z" class="navi-pin"/><circle cy="-2.2" r=".38" fill="#fff"/></g>';
    } else {
      svg += '<g transform="translate(' + (b[0] + 0.5) + ' ' + (b[1] + 0.5) + ')"><circle r=".85" class="navi-next-dot"/><text class="navi-dot-num" font-size="' + (i + 2 >= 10 ? '.78' : '.95') + '">' + (i + 2) + '</text></g>';
    }
    svg += '</svg>';
    var world = $('navi-world');
    var changed = shownMap !== s.map;
    world.innerHTML = '<img src="' + BASE + m.img + '" width="' + W + '" height="' + H + '" alt="">' +
      (m.over ? '<img src="' + BASE + m.over + '" width="' + W + '" height="' + H + '" alt="" class="navi-over">' : '') + svg;
    if (changed) { world.classList.remove('is-fade'); void world.offsetWidth; world.classList.add('is-fade'); }
    shownMap = s.map;
    $('navi-mapname').textContent = m.name;
  }

  function fitTo(i, animate) {
    var s = route.steps[i];
    var xs = s.pts.map(function (p) { return p[0]; }), ys = s.pts.map(function (p) { return p[1]; });
    var pad = 4;
    var x0 = (Math.min.apply(null, xs) - pad) * TILE, x1 = (Math.max.apply(null, xs) + 1 + pad) * TILE;
    var y0 = (Math.min.apply(null, ys) - pad) * TILE, y1 = (Math.max.apply(null, ys) + 1 + pad) * TILE;
    var box = $('navi-map').getBoundingClientRect();
    var top = $('navi-banner').hidden ? 0 : $('navi-banner').offsetHeight + 24, bottom = 64;
    var vw = box.width, vh = Math.max(80, box.height - top - bottom);
    var sc = Math.max(0.35, Math.min(2.5, vw / (x1 - x0), vh / (y1 - y0)));
    setView({ s: sc, x: vw / 2 - (x0 + x1) / 2 * sc, y: top + vh / 2 - (y0 + y1) / 2 * sc }, animate);
  }

  function setView(v, animate) {
    view = v;
    var w = $('navi-world');
    w.classList.toggle('is-anim', !!animate);
    w.style.transform = 'translate(' + v.x + 'px,' + v.y + 'px) scale(' + v.s + ')';
    w.classList.toggle('is-pixel', v.s > 1.2);
  }

  function go(i) {
    cur = i;
    var s = route.steps[i], n = route.steps[i + 1];
    var changed = shownMap !== s.map;
    var goal = i === route.steps.length - 1;
    drawMap(i);
    $('navi-banner').innerHTML = arrow(firstDir(s), goal) + '<div><div class="navi-banner-text">' + esc(s.text) + '</div>' +
      (s.dirs ? '<div class="navi-banner-dirs">' + esc(s.dirs) + '</div>' : '') + '</div>' +
      (n ? '<div class="navi-banner-next">次: ' + esc(n.text) + '</div>' : '');
    Array.prototype.forEach.call($('navi-steps').children, function (li, j) {
      li.classList.toggle('is-on', j === i);
    });
    // 横に並ぶときだけ、左の一覧を今の手順まで送る (縦に並ぶときはページごと動かさない)
    var li = $('navi-steps').children[i], panel = root.querySelector('.navi-panel');
    if (li && !stacked()) {
      var top = li.offsetTop - panel.offsetTop, bottom = top + li.offsetHeight;
      if (top < panel.scrollTop || bottom > panel.scrollTop + panel.clientHeight) {
        panel.scrollTo({ top: Math.max(0, top - 12), behavior: 'smooth' });
      }
    }
    $('navi-prev').disabled = i === 0;
    $('navi-next').disabled = goal;
    $('navi-next').textContent = goal ? '到着' : '次へ';
    requestAnimationFrame(function () { fitTo(i, !changed); });
  }

  // ---------------------------------------------------------------- 地図の操作

  function zoomAt(f, cx, cy) {
    var s = Math.max(0.25, Math.min(4, view.s * f)), k = s / view.s;
    setView({ s: s, x: cx - (cx - view.x) * k, y: cy - (cy - view.y) * k }, false);
  }

  function center() {
    var b = $('navi-map').getBoundingClientRect();
    return [b.width / 2, b.height / 2];
  }

  var stage = $('navi-stage'), ptrs = {}, last = null, pinch = null;
  stage.addEventListener('wheel', function (e) {
    if (!route) return;
    e.preventDefault();
    var b = stage.getBoundingClientRect();
    zoomAt(Math.exp(-e.deltaY * 0.0015), e.clientX - b.left, e.clientY - b.top);
  }, { passive: false });
  stage.addEventListener('pointerdown', function (e) {
    stage.setPointerCapture(e.pointerId);
    ptrs[e.pointerId] = e;
    stage.classList.add('is-drag');
    last = { x: e.clientX, y: e.clientY };
  });
  stage.addEventListener('pointermove', function (e) {
    if (!ptrs[e.pointerId]) return;
    ptrs[e.pointerId] = e;
    var ids = Object.keys(ptrs), b = stage.getBoundingClientRect();
    if (ids.length === 2) {
      var p = ptrs[ids[0]], q = ptrs[ids[1]];
      var d = Math.hypot(p.clientX - q.clientX, p.clientY - q.clientY);
      if (pinch) zoomAt(d / pinch, (p.clientX + q.clientX) / 2 - b.left, (p.clientY + q.clientY) / 2 - b.top);
      pinch = d;
      return;
    }
    if (last) setView({ s: view.s, x: view.x + e.clientX - last.x, y: view.y + e.clientY - last.y }, false);
    last = { x: e.clientX, y: e.clientY };
  });
  function up(e) {
    delete ptrs[e.pointerId];
    var ids = Object.keys(ptrs);
    if (ids.length < 2) pinch = null;
    if (!ids.length) { last = null; stage.classList.remove('is-drag'); }
    else last = { x: ptrs[ids[0]].clientX, y: ptrs[ids[0]].clientY };
  }
  stage.addEventListener('pointerup', up);
  stage.addEventListener('pointercancel', up);

  $('navi-zin').addEventListener('click', function () { var c = center(); zoomAt(1.4, c[0], c[1]); });
  $('navi-zout').addEventListener('click', function () { var c = center(); zoomAt(1 / 1.4, c[0], c[1]); });
  $('navi-fit').addEventListener('click', function () { if (route) fitTo(cur, true); });
  $('navi-prev').addEventListener('click', function () { if (route && cur > 0) go(cur - 1); });
  $('navi-next').addEventListener('click', function () { if (route && cur < route.steps.length - 1) go(cur + 1); });
  $('navi-go').addEventListener('click', start);
  $('navi-swap').addEventListener('click', function () {
    var a = $('navi-from').value;
    $('navi-from').value = $('navi-to').value;
    $('navi-to').value = a;
  });
  $('navi-prog').addEventListener('change', function () { route = null; selectChapter(this.value); });
  window.addEventListener('resize', function () { if (route) fitTo(cur, false); });

  // ---------------------------------------------------------------- はじめ

  var params = new URLSearchParams(location.search);
  var key = params.get('p') || root.getAttribute('data-default');
  var prog = $('navi-prog');
  if (Array.prototype.some.call(prog.options, function (o) { return o.value === key && !o.disabled; })) prog.value = key;
  else prog.value = root.getAttribute('data-default');
  selectChapter(prog.value).then(function () {
    var a = params.get('from'), b = params.get('to');
    if (data && a && b && data.routes[a + '>' + b]) {
      $('navi-from').value = a;
      $('navi-to').value = b;
      start();
    }
  });
})();
