// 表示モードの切り替え。
// 要素が無い場合に落とさないようにしてある。ここで例外が出ると、この
// ファイルの以降の処理 (章内目次・わざの説明など) がまとめて動かなくなる。
(function () {
  var toggle = document.getElementById("nightModeToggle");
  var icon = document.getElementById("nightModeIcon");

  if (localStorage.getItem("nightMode") === "enabled") {
    document.body.classList.add("night-mode");
    if (icon) icon.src = "/assets/images/night.png";
  }

  if (!toggle) return;
  toggle.addEventListener("click", function () {
    document.body.classList.toggle("night-mode");
    var on = document.body.classList.contains("night-mode");
    if (icon) icon.src = on ? "/assets/images/night.png" : "/assets/images/day.png";
    localStorage.setItem("nightMode", on ? "enabled" : "disabled");
  });
})();


// 画面下端に固定表示される広告 (AdSense のアンカー広告) と、右下の「先頭へ」
// ボタンが重なる。広告の高さは配信されるまで分からず、配信ごとにも変わるので、
// 数字を決め打ちせず実際に置かれた要素を測って CSS 変数に入れる。
// 使うのは #toTopButton の bottom (style.scss)。
// 見つからなければ 0 のままで、今までと同じ位置に出る。
(function () {
  var last = -1;

  // body 直下で「画面の下端に貼り付いている fixed 要素」の高さを返す。
  // アンカー広告は上部に出す設定もあるので、下端のものだけを数える。
  function overlayHeight() {
    var vh = window.innerHeight;
    var max = 0;
    var kids = document.body.children;
    for (var i = 0; i < kids.length; i++) {
      var el = kids[i];
      if (el.id === "toTopButton") continue;
      var st = window.getComputedStyle(el);
      if (st.position !== "fixed") continue;
      if (st.display === "none" || st.visibility === "hidden") continue;
      var r = el.getBoundingClientRect();
      if (r.height <= 0 || r.bottom < vh - 2 || r.top > vh) continue;
      if (r.height > max) max = r.height;
    }
    return Math.round(max);
  }

  function update() {
    var h = overlayHeight();
    if (h === last) return;
    last = h;
    document.documentElement.style.setProperty("--overlay-bottom", h + "px");
  }

  // scroll ごとに測ると重いので、描画の1フレームに1回までにまとめる。
  var pending = false;
  function schedule() {
    if (pending) return;
    pending = true;
    window.requestAnimationFrame(function () {
      pending = false;
      update();
    });
  }

  window.addEventListener("load", schedule);
  window.addEventListener("resize", schedule);
  window.addEventListener("scroll", schedule, { passive: true });
  // 広告は読み込みのあとから差し込まれる。body 直下の増減を見て測り直す。
  if (window.MutationObserver) {
    new MutationObserver(schedule).observe(document.body, { childList: true });
  }
  schedule();
})();


$(document).ready(function () {
  // Enables images to open into new tab on click
  $("img.tabImage").each(function () {
    $(this).attr("onclick", "window.open(this.src, '_blank');")
  });

  // When the user scrolls down 20px from the top of the document, show the button
  window.onscroll = () => {
    btn = document.getElementById("toTopButton")
    if (document.body.scrollTop > 20 || document.documentElement.scrollTop > 20) {
      btn.style.display = "block";
    } else {
      btn.style.display = "none";
    }
  }
});

// When the user clicks on the button, scroll to the top of the document
function topFunction() {
  document.body.scrollTop = 0; // For Safari
  document.documentElement.scrollTop = 0; // For Chrome, Firefox, IE and Opera
}

$(document).ready(function() {
  // Hide additional header rows and content rows initially for each trainer_section
  $('.trainer_section .table-header tr:not(:first-child)').hide();
  $('.trainer_section tbody').hide();

  // Enter と Space でも開閉できるようにする。role と tabindex は生成側で
  // 付けてある。Space は既定だとページが送られるので抑える。
  $('.trainer_section .show-hide-text').on('keydown', function (ev) {
    if (ev.key !== 'Enter' && ev.key !== ' ' && ev.key !== 'Spacebar') return;
    ev.preventDefault();
    $(this).trigger('click');
  });

  // Add click event handler to toggle visibility and update button text for each show-hide-text
  $('.trainer_section .show-hide-text').click(function() {
    var headerRows = $(this).closest('.trainer_section').find('.table-header tr:not(:first-child)');
    var tableBody = $(this).closest('.trainer_section').find('tbody');

    if (headerRows.is(':visible') && tableBody.is(':visible')) {
      headerRows.hide();
      tableBody.hide();
      $(this).text($(this).data('show') || '[show]');
    } else {
      headerRows.show();
      tableBody.show();
      $(this).text($(this).data('hide') || '[hide]');
    }
  });
});

// 章内の節目次。狭い画面では畳んでおき、広い画面では読んでいる節を印す。
(function () {
  var toc = document.querySelector('.page-toc');
  if (!toc) return;

  // 1段組に落ちる幅では、開いたままだと本文が下に押し出される
  if (window.matchMedia('(max-width: 1100px)').matches) toc.open = false;

  var links = Array.prototype.slice.call(toc.querySelectorAll('a[href^="#"]'));
  if (!links.length) return;

  // 見出しとリンクの対。IntersectionObserver ではなくスクロール位置で
  // 判定する。見出しは1章あたり20前後しかないので総当たりで足り、
  // 「帯に入っているか」ではなく「どこまで読み進めたか」を素直に表せる。
  var items = [];
  links.forEach(function (a) {
    var el = document.getElementById(decodeURIComponent(a.hash.slice(1)));
    if (el) items.push({ a: a, el: el });
  });
  if (!items.length) return;

  var current = null;
  function mark(a) {
    if (current === a) return;
    if (current) current.classList.remove('is-current');
    if (a) a.classList.add('is-current');
    current = a;
  }

  function update() {
    // 画面上部から 1/3 の位置を「今読んでいる行」とみなし、
    // そこを最後に通過した見出しを現在地とする。
    var line = window.innerHeight / 3;
    var found = null;
    for (var i = 0; i < items.length; i++) {
      if (items[i].el.getBoundingClientRect().top <= line) found = items[i].a;
      else break;
    }
    mark(found);
  }

  var ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(function () { ticking = false; update(); });
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll);
  update();
})();

// わざの説明。title 属性はマウスを乗せないと出ないので、タッチ環境向けに
// タップでも同じ内容を出す。説明文を DOM に持たせるとページが重くなるため
// (1ページに最大3千件ある)、title の中身をそのまま使い回す。
(function () {
  var moves = document.querySelectorAll('.move-name[title]');
  if (!moves.length) return;

  var pop = null;
  function close() { if (pop) { pop.remove(); pop = null; } }

  moves.forEach(function (el) {
    el.addEventListener('click', function (ev) {
      ev.stopPropagation();
      var text = el.getAttribute('title');
      var isSame = pop && pop.dataset.owner === text;
      close();
      if (isSame) return;

      pop = document.createElement('div');
      pop.className = 'move-popup';
      pop.dataset.owner = text;
      pop.textContent = text;
      document.body.appendChild(pop);

      var r = el.getBoundingClientRect();
      var maxLeft = window.scrollX + document.documentElement.clientWidth - pop.offsetWidth - 8;
      pop.style.top = (window.scrollY + r.bottom + 6) + 'px';
      pop.style.left = Math.max(8, Math.min(window.scrollX + r.left, maxLeft)) + 'px';
    });
  });

  document.addEventListener('click', close);
  window.addEventListener('scroll', close, { passive: true });
})();

// ネタバレの開閉。
//
// 以前はクリックで開くだけで、閉じ直す手段が無いのに title には
// 「表示/非表示」と書かれていた。また <a> に href が無いためキーボードでは
// たどり着けなかった (role と tabindex は生成側で補っている)。
(function () {
  var buttons = document.querySelectorAll('.spoilerBtn');
  if (!buttons.length) return;

  buttons.forEach(function (btn) {
    var box = btn.parentElement && btn.parentElement.querySelector('.spoilerText');
    if (!box) return;

    // 閉じ直すための小さな操作子。開くときに一度だけ作る。
    var hide = null;

    function open() {
      box.style.display = 'block';
      btn.style.display = 'none';
      if (!hide) {
        hide = document.createElement('span');
        hide.className = 'spoilerHide';
        hide.setAttribute('role', 'button');
        hide.setAttribute('tabindex', '0');
        hide.textContent = btn.dataset.hide || 'hide';
        hide.addEventListener('click', close);
        hide.addEventListener('keydown', activate(close));
        box.insertBefore(hide, box.firstChild);
      }
      hide.focus();
    }

    function close() {
      box.style.display = 'none';
      btn.style.display = '';
      btn.focus();
    }

    btn.addEventListener('click', open);
    btn.addEventListener('keydown', activate(open));
  });

  // Enter と Space をクリックと同じ扱いにする。Space は既定だと
  // ページが送られてしまうので抑える。
  function activate(fn) {
    return function (ev) {
      if (ev.key !== 'Enter' && ev.key !== ' ' && ev.key !== 'Spacebar') return;
      ev.preventDefault();
      fn();
    };
  }
})();


// 絞り込みの結果が0件のときの文言。
//
// 「該当なし」とだけ出しても、次に何をすればいいのかが分からない。
// 条件を外す操作子はすぐ隣にあるので、その札の文字をそのまま借りて促す。
// 借りることで、英語で書き出したときも札と文言がずれない。
function refEmpty(bar) {
  var btn = bar && bar.querySelector('.ref-reset');
  var label = btn ? btn.textContent.trim() : '';
  return label ? '該当なし — 「' + label + '」で戻せます' : '該当なし';
}


// 出現場所ページ (/reborn/pokemon/) の絞り込み。
//
// 種族595行・場所2,528件を1枚に並べているので、ブラウザの検索だけでは
// 「みずタイプで、つりで捕れるもの」のような引き方ができない。
//
// 操作子は hidden 付きで書き出してあり、ここで初めて外す。JavaScript を
// 切っていても表は全件そのまま残り、Ctrl+F は今までどおり効く。
(function () {
  var bar = document.querySelector('.ref-filter');
  if (!bar) return;

  var input = document.getElementById('pdx-q');
  var countEl = bar.querySelector('.ref-count');
  var onlyEl = document.getElementById('pdx-only');
  var uptoEl = document.getElementById('pdx-upto');
  var resetEl = bar.querySelector('.ref-reset');
  var sortEl = document.getElementById('pdx-sort');
  var jump = document.querySelector('.pdx-jump');
  var tables = [].slice.call(document.querySelectorAll('.pdx-table'));
  var rows = [].slice.call(document.querySelectorAll('.pdx-table tr'));
  if (!rows.length) return;

  // 五十音順に並べ替えたときの状態。元の並びに戻せるよう、行がどの表の
  // 何番目にいたかを控えておく。
  var kanaMode = false;
  var home = rows.map(function (tr) { return tr.parentNode; });
  var jumpHome = jump ? jump.innerHTML : '';

  bar.hidden = false;

  // ひらがなで打っても片仮名の種族名に当たるようにする。全角英数と
  // 半角カナは NFKC で寄せてから、ひらがなを片仮名へ送る。
  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  // 行ごとの検索対象。地名や章の名前も含めたいので本文をそのまま使う。
  // 初回だけ組み立てて持っておく。
  rows.forEach(function (tr) {
    tr._hay = norm(
      (tr.getAttribute('data-name') || '') + ' ' +
      (tr.getAttribute('data-en') || '') + ' ' +
      tr.textContent
    );
    tr._types = (tr.getAttribute('data-types') || '').split(' ');
    tr._ways = (tr.getAttribute('data-ways') || '').split(' ');
    tr._only = tr.getAttribute('data-only') === '1';
    tr._places = [].slice.call(tr.querySelectorAll('li[data-way]'));
    tr._ch = parseInt(tr.getAttribute('data-ch'), 10) || 0;
    tr._places.forEach(function (li) {
      li._ch = parseInt(li.getAttribute('data-ch'), 10) || 0;
    });
  });

  var picked = { types: [], ways: [] };
  // 付録の持ち物の表から「この種族だけ」を開くための指定。名前の部分一致だと
  // 「ゴース」が「ゴースト」にも当たるので、内部シンボルで厳密に絞る。
  // 入力欄に手を入れた時点で解除し、以降はふつうの文字検索に戻す。
  var monKey = null;

  function chips(group) {
    return [].slice.call(bar.querySelectorAll('.ref-chips[data-group="' + group + '"] .ref-chip'));
  }

  function anySome(list, want) {
    if (!want.length) return true;
    for (var i = 0; i < want.length; i++) {
      if (list.indexOf(want[i]) !== -1) return true;
    }
    return false;
  }

  function apply() {
    var q = norm(input.value.trim());
    var terms = q ? q.split(/\s+/) : [];
    var onlyOne = onlyEl && onlyEl.checked;
    var upto = uptoEl && uptoEl.value !== '' ? parseInt(uptoEl.value, 10) : null;
    var shown = 0;

    rows.forEach(function (tr) {
      var ok = anySome(tr._types, picked.types) && anySome(tr._ways, picked.ways);
      if (ok && monKey) ok = tr.getAttribute('data-en') === monKey;
      if (ok && onlyOne) ok = tr._only;
      // その章までに行ける場所が1つでもあるか。場所は本文の順で並べて
      // あるので、行が持つのは一番早い章。
      if (ok && upto !== null) ok = tr._ch <= upto;
      for (var i = 0; ok && i < terms.length; i++) {
        if (tr._hay.indexOf(terms[i]) === -1) ok = false;
      }
      tr.hidden = !ok;
      if (ok) shown++;

      // 行の中で条件から外れた場所を落としておく。行は「条件に合う場所が
      // ある種族」で選んでいるので、絞ったのに外れた場所が同じ濃さで並ぶと
      // 読み違えるため。
      var dimming = picked.ways.length > 0 || upto !== null;
      if (ok && dimming) {
        tr._places.forEach(function (li) {
          var out = (picked.ways.length && picked.ways.indexOf(li.getAttribute('data-way')) === -1) ||
                    (upto !== null && li._ch > upto);
          li.classList.toggle('is-dim', out);
        });
      } else if (tr._dimmed) {
        tr._places.forEach(function (li) { li.classList.remove('is-dim'); });
      }
      tr._dimmed = ok && dimming;
    });

    // 空になった区切りは見出しごと畳む。五十音順のときは行が全部
    // 先頭の表へ移っているので、図鑑番号の見出しは常に伏せる。
    if (kanaMode) trimKanaHeads();
    tables.forEach(function (table) {
      var visible = false;
      var trs = table.rows;
      for (var i = 0; i < trs.length; i++) {
        if (!trs[i].hidden) { visible = true; break; }
      }
      table.hidden = !visible;
      var head = table.previousElementSibling;
      if (head && head.tagName === 'H2') head.hidden = kanaMode || !visible;
    });

    var filtering = terms.length > 0 || picked.types.length > 0 ||
                    picked.ways.length > 0 || onlyOne || upto !== null || monKey !== null;
    if (jump) jump.hidden = filtering;
    bar.classList.toggle('is-filtering', filtering);

    if (countEl) {
      countEl.textContent = filtering
        ? (shown === 0 ? refEmpty(bar) : rows.length + '件中 ' + shown + '件')
        : rows.length + '件';
    }
    remember(terms.length ? input.value.trim() : '');
  }

  // --- 五十音順への並べ替え ---------------------------------------
  //
  // 図鑑番号順は「進化の並び」で読める代わりに、名前しか知らないときに
  // 探せない。検索欄があるので優先度は低いが、通しで眺めたいときに効く。
  //
  // 並べ替えの鍵は、濁点・半濁点を落とし、小書きを大書きに直した片仮名。
  // 片仮名は符号位置がそのまま五十音の順なので、そのまま比べられる。
  var SMALL = {
    'ァ': 'ア', 'ィ': 'イ', 'ゥ': 'ウ', 'ェ': 'エ', 'ォ': 'オ', 'ッ': 'ツ',
    'ャ': 'ヤ', 'ュ': 'ユ', 'ョ': 'ヨ', 'ヮ': 'ワ', 'ヵ': 'カ', 'ヶ': 'ケ'
  };
  var GYO = [
    ['ア', 'アイウエオ'], ['カ', 'カキクケコ'], ['サ', 'サシスセソ'],
    ['タ', 'タチツテト'], ['ナ', 'ナニヌネノ'], ['ハ', 'ハヒフヘホ'],
    ['マ', 'マミムメモ'], ['ヤ', 'ヤユヨ'], ['ラ', 'ラリルレロ'],
    ['ワ', 'ワヲン']
  ];
  var GYO_OF = {};
  GYO.forEach(function (pair) {
    pair[1].split('').forEach(function (c) { GYO_OF[c] = pair[0]; });
  });

  // 長音符は直前の字の母音として読む。そうしないと「アブリー」が
  // 「アブリボン」の後ろに来る (ー の符号位置が片仮名より後ろのため)。
  var VOWEL = {};
  [['ア', 'アカサタナハマヤラワ'], ['イ', 'イキシチニヒミリ'],
   ['ウ', 'ウクスツヌフムユル'], ['エ', 'エケセテネヘメレ'],
   ['オ', 'オコソトノホモヨロヲ']].forEach(function (pair) {
    pair[1].split('').forEach(function (c) { VOWEL[c] = pair[0]; });
  });

  function collate(name) {
    var s = (name || '').normalize('NFD').replace(/[\u3099\u309A]/g, '');
    s = s.replace(/[ぁ-ゖ]/g, function (c) {
      return String.fromCharCode(c.charCodeAt(0) + 0x60);
    });
    s = s.replace(/[ァィゥェォッャュョヮヵヶ]/g, function (c) { return SMALL[c]; });
    var out = '';
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      out += (c === 'ー' && VOWEL[out.charAt(out.length - 1)]) ? VOWEL[out.charAt(out.length - 1)] : c;
    }
    return out.toUpperCase();
  }

  // 見出しに使う区切り。片仮名は行 (ア行・カ行…)、それ以外は頭文字。
  // WT_LANG=en で書き出すと種族名が英字になるため。
  function groupOf(key) {
    var head = key.charAt(0);
    if (GYO_OF[head]) return GYO_OF[head] + '行';
    return /[A-Z0-9]/.test(head) ? head : 'その他';
  }

  function kanaHead(label, id) {
    var tr = document.createElement('tr');
    tr.className = 'pdx-kana';
    tr.id = id;
    var th = document.createElement('th');
    th.colSpan = 2;
    th.textContent = label;
    tr.appendChild(th);
    return tr;
  }

  // 鍵は使うときに作る。並べ替えを開かなければ596回の変換は要らない。
  function keyOf(tr) {
    if (tr._key === undefined) tr._key = collate(tr.getAttribute('data-name'));
    return tr._key;
  }

  function toKana() {
    var host = tables[0];
    var sorted = rows.slice().sort(function (a, b) {
      var ka = keyOf(a), kb = keyOf(b);
      return ka < kb ? -1 : ka > kb ? 1 : 0;
    });
    var links = [], last = null, n = 0;
    sorted.forEach(function (tr) {
      var g = groupOf(keyOf(tr));
      if (g !== last) {
        if (last !== null) links[links.length - 1].n = n;
        var id = 'kana-' + links.length;
        host.appendChild(kanaHead(g, id));
        links.push({ id: id, label: g, n: 0 });
        last = g;
        n = 0;
      }
      n++;
      host.appendChild(tr);
    });
    if (links.length) links[links.length - 1].n = n;
    if (jump) {
      jump.innerHTML = links.map(function (l) {
        return '<li><a href="#' + l.id + '">' + l.label + '<span>' + l.n + '</span></a></li>';
      }).join('');
    }
    kanaMode = true;
  }

  function toDex() {
    [].slice.call(document.querySelectorAll('.pdx-kana')).forEach(function (tr) {
      tr.parentNode.removeChild(tr);
    });
    // 控えた表へ元の順に戻す。表には他の行が無いので、順に足せば復元できる。
    rows.forEach(function (tr, i) { home[i].appendChild(tr); });
    if (jump) jump.innerHTML = jumpHome;
    kanaMode = false;
  }

  // 見出しの下に見える行が1つも無ければ、見出しごと畳む。
  function trimKanaHeads() {
    var trs = tables[0].rows;
    var cur = null, seen = 0;
    for (var i = 0; i < trs.length; i++) {
      var tr = trs[i];
      if (tr.className === 'pdx-kana') {
        if (cur) cur.hidden = seen === 0;
        cur = tr;
        seen = 0;
      } else if (!tr.hidden) {
        seen++;
      }
    }
    if (cur) cur.hidden = seen === 0;
  }

  if (sortEl) {
    sortEl.addEventListener('change', function () {
      if (sortEl.value === 'kana') { if (!kanaMode) toKana(); }
      else if (kanaMode) toDex();
      apply();
    });
  }

  // 絞り込んだ状態をそのまま渡せるように、条件を URL に残す。
  // location.hash を落とさないこと。落とすと、他のページから
  // /reborn/pokemon/#mon-xxx で飛んできたときに、ブラウザがまだ位置を
  // 合わせる前に飛び先が消えて、先頭に留まってしまう。
  function remember(q) {
    if (!window.history || !history.replaceState) return;
    var p = new URLSearchParams();
    // ?mon= のときの入力欄の中身は「何で絞っているか」を見せる札なので、
    // q として二重に書かない。手で打ち直せば monKey が外れて q に戻る。
    if (q && !monKey) p.set('q', q);
    if (monKey) p.set('mon', monKey);
    if (picked.types.length) p.set('t', picked.types.join(','));
    if (picked.ways.length) p.set('w', picked.ways.join(','));
    if (onlyEl && onlyEl.checked) p.set('only', '1');
    if (uptoEl && uptoEl.value !== '') p.set('ch', uptoEl.value);
    if (kanaMode) p.set('s', 'kana');
    var s = p.toString();
    history.replaceState(null, '', (s ? '?' + s : location.pathname) + location.hash);
  }

  function bindChips(group) {
    chips(group).forEach(function (chip) {
      chip.setAttribute('aria-pressed', 'false');
      chip.addEventListener('click', function () {
        var v = chip.getAttribute('data-value');
        var at = picked[group].indexOf(v);
        if (at === -1) picked[group].push(v); else picked[group].splice(at, 1);
        chip.classList.toggle('is-on', at === -1);
        chip.setAttribute('aria-pressed', at === -1 ? 'true' : 'false');
        apply();
      });
    });
  }

  bindChips('types');
  bindChips('ways');

  var timer = null;
  input.addEventListener('input', function () {
    monKey = null;
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });

  if (onlyEl) onlyEl.addEventListener('change', apply);
  if (uptoEl) uptoEl.addEventListener('change', apply);

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      monKey = null;
      picked.types = [];
      picked.ways = [];
      ['types', 'ways'].forEach(function (g) {
        chips(g).forEach(function (c) {
          c.classList.remove('is-on');
          c.setAttribute('aria-pressed', 'false');
        });
      });
      if (onlyEl) onlyEl.checked = false;
      if (uptoEl) uptoEl.value = '';
      if (sortEl) { sortEl.value = 'dex'; if (kanaMode) toDex(); }
      apply();
      input.focus();
    });
  }

  // 「/」で検索欄へ。入力中は邪魔しない。
  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  // 共有された URL の条件を復元する。
  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('q')) input.value = p.get('q');
    // ?mon= で来たときは、何で絞られているか分かるように種族名を欄へ入れる。
    if (p.get('mon')) {
      monKey = p.get('mon');
      var target = null;
      for (var n = 0; n < rows.length; n++) {
        if (rows[n].getAttribute('data-en') === monKey) { target = rows[n]; break; }
      }
      if (target) input.value = target.getAttribute('data-name') || '';
      else monKey = null;
    }
    ['types', 'ways'].forEach(function (g) {
      var raw = p.get(g === 'types' ? 't' : 'w');
      if (!raw) return;
      raw.split(',').forEach(function (v) {
        var chip = bar.querySelector('.ref-chips[data-group="' + g + '"] .ref-chip[data-value="' + v + '"]');
        if (!chip) return;
        picked[g].push(v);
        chip.classList.add('is-on');
        chip.setAttribute('aria-pressed', 'true');
      });
    });
    if (onlyEl && p.get('only') === '1') onlyEl.checked = true;
    if (uptoEl && p.get('ch')) uptoEl.value = p.get('ch');
    if (sortEl && p.get('s') === 'kana') { sortEl.value = 'kana'; toKana(); }
  })();

  apply();

  // ?mon= で1種に絞って開いたときは、その行まで送る。絞ったあとでも
  // 前置きと操作子で 800px ほど埋まっており、結果が画面の外に残るため。
  if (monKey) {
    for (var k = 0; k < rows.length; k++) {
      if (!rows[k].hidden) {
        rows[k].scrollIntoView({ block: 'center' });
        break;
      }
    }
  }
})();


// フィールド効果ページ (/reborn/fields/) の絞り込み。
//
// 38フィールド・820行あるので、「こおり技が強化されるのはどこか」を
// 横断で引けるようにする。操作子の体裁 (.ref-*) は出現場所ページと同じ。
(function () {
  var bar = document.querySelector('.fn-filter');
  if (!bar) return;

  var input = document.getElementById('fn-q');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var jump = document.querySelector('.fn-jump');
  var lists = [].slice.call(document.querySelectorAll('.field-notes'));
  if (!lists.length) return;

  bar.hidden = false;

  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  // 1フィールド分のまとまり。見出し・台詞・効果の一覧・戦う場面を
  // ひとまとめにして、まるごと出し入れする。
  var groups = lists.map(function (ul) {
    var head = ul.previousElementSibling;
    var parts = [ul];
    while (head && head.tagName !== 'H2') {
      parts.push(head);
      head = head.previousElementSibling;
    }
    var after = ul.nextElementSibling;
    if (after && after.classList.contains('fn-usage')) parts.push(after);

    var items = [].slice.call(ul.querySelectorAll('li'));
    items.forEach(function (li) {
      li._hay = norm(li.textContent);
      li._types = (li.getAttribute('data-types') || '').split(' ');
    });

    return {
      head: head,
      parts: parts,
      items: items,
      name: norm(head ? head.textContent : ''),
      id: head ? head.id : null
    };
  });

  var totalItems = groups.reduce(function (n, g) { return n + g.items.length; }, 0);
  var picked = [];

  // 飛び先一覧は絞り込み中も残す。当たったフィールドだけに減らし、
  // 数字を「そのフィールドの中で当たった行数」に差し替える。
  var navItems = jump ? [].slice.call(jump.querySelectorAll('li')).map(function (li) {
    var a = li.querySelector('a');
    var num = a ? a.querySelector('span') : null;
    return {
      li: li,
      num: num,
      total: num ? num.textContent : '',
      id: a ? a.getAttribute('href').slice(1) : null
    };
  }) : [];

  function chipEls() {
    return [].slice.call(bar.querySelectorAll('.ref-chip'));
  }

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var shownFields = 0;
    var shownItems = 0;

    var filtering = terms.length > 0 || picked.length > 0;
    var hitsById = {};

    groups.forEach(function (g) {
      // フィールドの名前自体が当たっているなら、その中身は文字での
      // 絞り込みを通す。「森林フィールド」と打って中身が消えると困る。
      var nameHit = terms.length > 0 && terms.every(function (t) {
        return g.name.indexOf(t) !== -1;
      });
      var hits = 0;

      g.items.forEach(function (li) {
        var ok = true;
        if (picked.length) {
          ok = false;
          for (var i = 0; i < picked.length; i++) {
            if (li._types.indexOf(picked[i]) !== -1) { ok = true; break; }
          }
        }
        if (ok && terms.length) {
          for (var j = 0; j < terms.length; j++) {
            if (li._hay.indexOf(terms[j]) === -1) { ok = false; break; }
          }
        }
        if (ok) hits++;
        // 当たった行に印を付けるだけで、行は消さない。フィールドは効果の
        // 組み合わせで判断するものなので、1行だけ抜き出しても使えない。
        li.classList.toggle('is-hit', filtering && ok && !nameHit);
      });

      var show = !filtering || nameHit || hits > 0;
      g.parts.forEach(function (el) { el.hidden = !show; });
      if (g.head) g.head.hidden = !show;
      if (show) {
        shownFields++;
        shownItems += nameHit ? g.items.length : hits;
        if (g.id) hitsById[g.id] = nameHit ? g.items.length : hits;
      }
    });

    navItems.forEach(function (n) {
      var hit = n.id ? hitsById[n.id] : undefined;
      n.li.hidden = filtering && hit === undefined;
      if (n.num) n.num.textContent = filtering && hit !== undefined ? hit : n.total;
    });

    bar.classList.toggle('is-filtering', filtering);

    if (countEl) {
      countEl.textContent = filtering
        ? (shownFields === 0 ? refEmpty(bar)
            : shownFields + 'フィールド / ' + shownItems + '行が一致')
        : groups.length + 'フィールド / ' + totalItems + '行';
    }

    if (window.history && history.replaceState) {
      var p = new URLSearchParams();
      if (input.value.trim()) p.set('q', input.value.trim());
      if (picked.length) p.set('t', picked.join(','));
      var s = p.toString();
      // location.hash を落とさないこと。落とすと、他のページから
      // 節の見出しへ飛んできたときに、ブラウザがまだ位置を合わせる前に
      // 飛び先が消えて、先頭に留まってしまう。
      history.replaceState(null, '', (s ? '?' + s : location.pathname) + location.hash);
    }
  }

  chipEls().forEach(function (chip) {
    chip.setAttribute('aria-pressed', 'false');
    chip.addEventListener('click', function () {
      var v = chip.getAttribute('data-value');
      var at = picked.indexOf(v);
      if (at === -1) picked.push(v); else picked.splice(at, 1);
      chip.classList.toggle('is-on', at === -1);
      chip.setAttribute('aria-pressed', at === -1 ? 'true' : 'false');
      apply();
    });
  });

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      picked = [];
      chipEls().forEach(function (c) {
        c.classList.remove('is-on');
        c.setAttribute('aria-pressed', 'false');
      });
      apply();
      input.focus();
    });
  }

  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('q')) input.value = p.get('q');
    var raw = p.get('t');
    if (raw) {
      raw.split(',').forEach(function (v) {
        var chip = bar.querySelector('.ref-chip[data-value="' + v + '"]');
        if (!chip) return;
        picked.push(v);
        chip.classList.add('is-on');
        chip.setAttribute('aria-pressed', 'true');
      });
    }
  })();

  apply();
})();


// 付録のパスワード一覧 (/reborn/appendices/) の絞り込み。
//
// 215語が6分類に並んでいるだけで、目で追うしかなかった。項目は生の原稿に
// 手で書かれた箇条書きと、生成したフィールド指定の表の2種類がある。
// どちらも「1件」として同じように扱う。
(function () {
  var bar = document.querySelector('.pw-filter');
  if (!bar) return;

  var input = document.getElementById('pw-q');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var chips = [].slice.call(bar.querySelectorAll('.pw-chip'));
  if (!chips.length) return;

  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  // 分類ごとに、見出しから次の見出しまでの要素をまとめて持つ。
  var groups = chips.map(function (chip) {
    var id = chip.getAttribute('data-value');
    var head = document.getElementById(id);
    var parts = [];
    var items = [];
    var el = head ? head.nextElementSibling : null;
    while (el && el.tagName !== 'H3' && el.tagName !== 'H2') {
      parts.push(el);
      [].slice.call(el.querySelectorAll('li')).forEach(function (li) { items.push(li); });
      [].slice.call(el.querySelectorAll('tr[data-pw]')).forEach(function (tr) { items.push(tr); });
      el = el.nextElementSibling;
    }
    items.forEach(function (it) { it._hay = norm(it.textContent); });
    return { id: id, head: head, parts: parts, items: items };
  });

  var total = groups.reduce(function (n, g) { return n + g.items.length; }, 0);
  var picked = [];

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var filtering = terms.length > 0 || picked.length > 0;
    var shown = 0;

    groups.forEach(function (g) {
      var inCat = !picked.length || picked.indexOf(g.id) !== -1;
      var any = false;

      g.items.forEach(function (it) {
        var ok = inCat;
        for (var i = 0; ok && i < terms.length; i++) {
          if (it._hay.indexOf(terms[i]) === -1) ok = false;
        }
        it.hidden = !ok;
        if (ok) { any = true; shown++; }
      });

      // 中身が全部消えた分類は、見出しと前置きごと畳む。
      g.parts.forEach(function (el) { el.hidden = !any; });
      if (g.head) g.head.hidden = !any;
    });

    bar.classList.toggle('is-filtering', filtering);
    if (countEl) {
      countEl.textContent = filtering
        ? (shown === 0 ? refEmpty(bar) : total + '件中 ' + shown + '件')
        : total + '件';
    }

    if (window.history && history.replaceState) {
      var p = new URLSearchParams();
      if (input.value.trim()) p.set('pw', input.value.trim());
      if (picked.length) p.set('g', picked.join(','));
      var s = p.toString();
      // location.hash を落とさないこと。落とすと、他のページから
      // 節の見出しへ飛んできたときに、ブラウザがまだ位置を合わせる前に
      // 飛び先が消えて、先頭に留まってしまう。
      history.replaceState(null, '', (s ? '?' + s : location.pathname) + location.hash);
    }
  }

  chips.forEach(function (chip) {
    chip.setAttribute('aria-pressed', 'false');
    chip.addEventListener('click', function () {
      var v = chip.getAttribute('data-value');
      var at = picked.indexOf(v);
      if (at === -1) picked.push(v); else picked.splice(at, 1);
      chip.classList.toggle('is-on', at === -1);
      chip.setAttribute('aria-pressed', at === -1 ? 'true' : 'false');
      apply();
    });
  });

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });

  function clearAll() {
    input.value = '';
    picked = [];
    chips.forEach(function (c) {
      c.classList.remove('is-on');
      c.setAttribute('aria-pressed', 'false');
    });
    apply();
  }

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      clearAll();
      input.focus();
    });
  }

  // まとめパスワードの中身から各項目へ飛べるようにしてあるが、絞り込みで
  // 飛び先が隠れていると押しても何も起きない。そのときだけ条件を外す。
  document.addEventListener('click', function (ev) {
    var t = ev.target;
    var a = t && t.closest ? t.closest('a[href^="#pw-"]') : null;
    if (!a) return;
    var el = document.getElementById(a.getAttribute('href').slice(1));
    var li = el && el.closest ? el.closest('li') : null;
    if (!li || !li.hidden) return;
    clearAll();
  });

  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('pw')) input.value = p.get('pw');
    var raw = p.get('g');
    if (raw) {
      raw.split(',').forEach(function (v) {
        var chip = bar.querySelector('.pw-chip[data-value="' + v + '"]');
        if (!chip) return;
        picked.push(v);
        chip.classList.add('is-on');
        chip.setAttribute('aria-pressed', 'true');
      });
    }
  })();

  bar.hidden = false;
  apply();
})();


// 目次ページ (/reborn/) の絞り込み。
//
// 攻略本文29章には検索が無く、何かを探すには 11.7MB の一枚版を開いて
// ブラウザの検索を使うしかなかった。目次にはすでに全章・全節の見出しと
// リンクが並んでいるので (30ブロック / 277項目)、ここを索引として引く。
(function () {
  var bar = document.querySelector('.toc-filter');
  if (!bar) return;

  var input = document.getElementById('toc-q');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var blocks = [].slice.call(document.querySelectorAll('.book-toc-chapter'));
  if (!blocks.length) return;

  bar.hidden = false;

  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  var groups = blocks.map(function (block) {
    var head = block.querySelector('h3');
    var items = [].slice.call(block.querySelectorAll('li'));
    // 見出しの文字に加えて、その節に出てくるトレーナー名とショップ名も
    // 対象にする (data-keys)。人名で引けないと索引として使いにくい。
    items.forEach(function (li) {
      li._hay = norm(li.textContent + ' ' + (li.getAttribute('data-keys') || ''));
    });
    return { block: block, name: norm(head ? head.textContent : ''), items: items };
  });

  var total = groups.reduce(function (n, g) { return n + g.items.length; }, 0);

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var filtering = terms.length > 0;
    var shownBlocks = 0;
    var shownItems = 0;

    groups.forEach(function (g) {
      // 章の名前が当たっているときは、その中身は丸ごと残す。章名で
      // 引いたのに節が消えると、どこを開けばよいか分からなくなる。
      var nameHit = filtering && terms.every(function (t) { return g.name.indexOf(t) !== -1; });
      var hits = 0;

      g.items.forEach(function (li) {
        var ok = true;
        for (var i = 0; ok && i < terms.length; i++) {
          if (li._hay.indexOf(terms[i]) === -1) ok = false;
        }
        if (ok) hits++;
        li.hidden = filtering && !nameHit && !ok;
      });

      var show = !filtering || nameHit || hits > 0;
      g.block.hidden = !show;
      if (show) {
        shownBlocks++;
        shownItems += nameHit ? g.items.length : hits;
      }
    });

    bar.classList.toggle('is-filtering', filtering);
    if (countEl) {
      countEl.textContent = filtering
        ? (shownItems === 0 ? refEmpty(bar) : shownBlocks + '章 / ' + shownItems + '項目')
        : groups.length + '章 / ' + total + '項目';
    }

    if (window.history && history.replaceState) {
      var q = input.value.trim();
      history.replaceState(null, '', (q ? '?q=' + encodeURIComponent(q) : location.pathname) + location.hash);
    }
  }

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      apply();
      input.focus();
    });
  }

  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  var p = new URLSearchParams(location.search);
  if (p.get('q')) input.value = p.get('q');
  apply();
})();


// どうぐの買える店 (/reborn/shops/) の絞り込み。
//
// 347品目 / 519件。どうぐ名でも店名でも引ける。
(function () {
  var bar = document.querySelector('.sh-filter');
  if (!bar) return;

  var input = document.getElementById('sh-q');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var manyEl = document.getElementById('sh-many');
  var uptoEl = document.getElementById('sh-upto');
  var rows = [].slice.call(document.querySelectorAll('.sh-table tr'));
  if (!rows.length) return;

  bar.hidden = false;

  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  rows.forEach(function (tr) {
    tr._hay = norm(tr.textContent);
    tr._shops = parseInt(tr.getAttribute('data-shops'), 10) || 1;
    tr._ch = parseInt(tr.getAttribute('data-ch'), 10) || 0;
    tr._places = [].slice.call(tr.querySelectorAll('li[data-ch]'));
    tr._places.forEach(function (li) {
      li._ch = parseInt(li.getAttribute('data-ch'), 10) || 0;
    });
  });

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var many = manyEl && manyEl.checked;
    var upto = uptoEl && uptoEl.value !== '' ? parseInt(uptoEl.value, 10) : null;
    var shown = 0;

    rows.forEach(function (tr) {
      var ok = true;
      if (many) ok = tr._shops > 1;
      if (ok && upto !== null) ok = tr._ch <= upto;
      for (var i = 0; ok && i < terms.length; i++) {
        if (tr._hay.indexOf(terms[i]) === -1) ok = false;
      }
      tr.hidden = !ok;
      if (ok) shown++;

      // その章までに行けない店は落としておく。行は「その章までに買える
      // どうぐ」で選んでいるので、先の店が同じ濃さで並ぶと読み違える。
      if (ok && upto !== null) {
        tr._places.forEach(function (li) { li.classList.toggle('is-dim', li._ch > upto); });
      } else if (tr._dimmed) {
        tr._places.forEach(function (li) { li.classList.remove('is-dim'); });
      }
      tr._dimmed = ok && upto !== null;
    });

    var filtering = terms.length > 0 || many || upto !== null;
    bar.classList.toggle('is-filtering', filtering);
    if (countEl) {
      countEl.textContent = filtering
        ? (shown === 0 ? refEmpty(bar) : rows.length + '件中 ' + shown + '件')
        : rows.length + '件';
    }

    if (window.history && history.replaceState) {
      var p = new URLSearchParams();
      if (input.value.trim()) p.set('q', input.value.trim());
      if (many) p.set('many', '1');
      if (upto !== null) p.set('ch', uptoEl.value);
      var s = p.toString();
      history.replaceState(null, '', (s ? '?' + s : location.pathname) + location.hash);
    }
  }

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });
  if (manyEl) manyEl.addEventListener('change', apply);
  if (uptoEl) uptoEl.addEventListener('change', apply);

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      if (manyEl) manyEl.checked = false;
      if (uptoEl) uptoEl.value = '';
      apply();
      input.focus();
    });
  }

  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('q')) input.value = p.get('q');
    if (manyEl && p.get('many') === '1') manyEl.checked = true;
    if (uptoEl && p.get('ch')) uptoEl.value = p.get('ch');
    if (sortEl && p.get('s') === 'kana') { sortEl.value = 'kana'; toKana(); }
  })();

  apply();
})();


// わざマシン一覧 (/reborn/tms/) の絞り込み。
//
// 109本。番号・わざ名・地名の文字検索、タイプ、進行度、記載の有無。
(function () {
  var bar = document.querySelector('.tm-filter');
  if (!bar) return;

  var input = document.getElementById('tm-q');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var missEl = document.getElementById('tm-missing');
  var uptoEl = document.getElementById('tm-upto');
  var rows = [].slice.call(document.querySelectorAll('.tm-table tr'));
  if (!rows.length) return;

  bar.hidden = false;

  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  rows.forEach(function (tr) {
    tr._hay = norm(tr.textContent);
    tr._types = (tr.getAttribute('data-types') || '').split(' ');
    tr._ch = parseInt(tr.getAttribute('data-ch'), 10);
    tr._has = tr.getAttribute('data-has') === '1';
    tr._places = [].slice.call(tr.querySelectorAll('li[data-ch]'));
    tr._places.forEach(function (li) { li._ch = parseInt(li.getAttribute('data-ch'), 10) || 0; });
  });

  var picked = [];

  function chipEls() {
    return [].slice.call(bar.querySelectorAll('.ref-chip'));
  }

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var missingOnly = missEl && missEl.checked;
    var upto = uptoEl && uptoEl.value !== '' ? parseInt(uptoEl.value, 10) : null;
    var shown = 0;

    rows.forEach(function (tr) {
      var ok = true;
      if (picked.length) {
        ok = false;
        for (var i = 0; i < picked.length; i++) {
          if (tr._types.indexOf(picked[i]) !== -1) { ok = true; break; }
        }
      }
      if (ok && missingOnly) ok = !tr._has;
      // 記載の無いものは章を持たないので、進行度で絞ると外れる。
      if (ok && upto !== null) ok = tr._has && tr._ch <= upto;
      for (var j = 0; ok && j < terms.length; j++) {
        if (tr._hay.indexOf(terms[j]) === -1) ok = false;
      }
      tr.hidden = !ok;
      if (ok) shown++;

      if (ok && upto !== null) {
        tr._places.forEach(function (li) { li.classList.toggle('is-dim', li._ch > upto); });
      } else if (tr._dimmed) {
        tr._places.forEach(function (li) { li.classList.remove('is-dim'); });
      }
      tr._dimmed = ok && upto !== null;
    });

    var filtering = terms.length > 0 || picked.length > 0 || missingOnly || upto !== null;
    bar.classList.toggle('is-filtering', filtering);
    if (countEl) {
      countEl.textContent = filtering
        ? (shown === 0 ? refEmpty(bar) : rows.length + '本中 ' + shown + '本')
        : rows.length + '本';
    }

    if (window.history && history.replaceState) {
      var p = new URLSearchParams();
      if (input.value.trim()) p.set('q', input.value.trim());
      if (picked.length) p.set('t', picked.join(','));
      if (missingOnly) p.set('none', '1');
      if (upto !== null) p.set('ch', uptoEl.value);
      var s = p.toString();
      history.replaceState(null, '', (s ? '?' + s : location.pathname) + location.hash);
    }
  }

  chipEls().forEach(function (chip) {
    chip.setAttribute('aria-pressed', 'false');
    chip.addEventListener('click', function () {
      var v = chip.getAttribute('data-value');
      var at = picked.indexOf(v);
      if (at === -1) picked.push(v); else picked.splice(at, 1);
      chip.classList.toggle('is-on', at === -1);
      chip.setAttribute('aria-pressed', at === -1 ? 'true' : 'false');
      apply();
    });
  });

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });
  if (missEl) missEl.addEventListener('change', apply);
  if (uptoEl) uptoEl.addEventListener('change', apply);

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      picked = [];
      chipEls().forEach(function (c) {
        c.classList.remove('is-on');
        c.setAttribute('aria-pressed', 'false');
      });
      if (missEl) missEl.checked = false;
      if (uptoEl) uptoEl.value = '';
      apply();
      input.focus();
    });
  }

  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('q')) input.value = p.get('q');
    var raw = p.get('t');
    if (raw) {
      raw.split(',').forEach(function (v) {
        var chip = bar.querySelector('.ref-chip[data-value="' + v + '"]');
        if (!chip) return;
        picked.push(v);
        chip.classList.add('is-on');
        chip.setAttribute('aria-pressed', 'true');
      });
    }
    if (missEl && p.get('none') === '1') missEl.checked = true;
    if (uptoEl && p.get('ch')) uptoEl.value = p.get('ch');
    if (sortEl && p.get('s') === 'kana') { sortEl.value = 'kana'; toKana(); }
  })();

  apply();
})();


// 進化条件の一覧 (/reborn/evolutions/) の絞り込み。
//
// 394件。種族名・どうぐ名・わざ名の文字検索と、進化の仕方の分類。
(function () {
  var bar = document.querySelector('.ev-filter');
  if (!bar) return;

  var input = document.getElementById('ev-q');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var rows = [].slice.call(document.querySelectorAll('.ev-table tr'));
  if (!rows.length) return;

  bar.hidden = false;

  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  rows.forEach(function (tr) {
    tr._hay = norm(tr.textContent);
    tr._group = tr.getAttribute('data-group');
  });

  var picked = [];

  function chipEls() {
    return [].slice.call(bar.querySelectorAll('.ev-chip'));
  }

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var shown = 0;

    rows.forEach(function (tr) {
      var ok = !picked.length || picked.indexOf(tr._group) !== -1;
      for (var i = 0; ok && i < terms.length; i++) {
        if (tr._hay.indexOf(terms[i]) === -1) ok = false;
      }
      tr.hidden = !ok;
      if (ok) shown++;
    });

    var filtering = terms.length > 0 || picked.length > 0;
    bar.classList.toggle('is-filtering', filtering);
    if (countEl) {
      countEl.textContent = filtering
        ? (shown === 0 ? refEmpty(bar) : rows.length + '件中 ' + shown + '件')
        : rows.length + '件';
    }

    if (window.history && history.replaceState) {
      var p = new URLSearchParams();
      if (input.value.trim()) p.set('q', input.value.trim());
      if (picked.length) p.set('g', picked.join(','));
      var s = p.toString();
      history.replaceState(null, '', (s ? '?' + s : location.pathname) + location.hash);
    }
  }

  chipEls().forEach(function (chip) {
    chip.setAttribute('aria-pressed', 'false');
    chip.addEventListener('click', function () {
      var v = chip.getAttribute('data-value');
      var at = picked.indexOf(v);
      if (at === -1) picked.push(v); else picked.splice(at, 1);
      chip.classList.toggle('is-on', at === -1);
      chip.setAttribute('aria-pressed', at === -1 ? 'true' : 'false');
      apply();
    });
  });

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      picked = [];
      chipEls().forEach(function (c) {
        c.classList.remove('is-on');
        c.setAttribute('aria-pressed', 'false');
      });
      apply();
      input.focus();
    });
  }

  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('q')) input.value = p.get('q');
    var raw = p.get('g');
    if (raw) {
      raw.split(',').forEach(function (v) {
        var chip = bar.querySelector('.ev-chip[data-value="' + v + '"]');
        if (!chip) return;
        picked.push(v);
        chip.classList.add('is-on');
        chip.setAttribute('aria-pressed', 'true');
      });
    }
  })();

  apply();
})();


// 好感度まとめ (/reborn/affinity/) の絞り込み。
//
// 35人 / 419行。人物名でも選択肢の文でも引ける。
//
// 節の欄は rowspan でまとめてあるので、行を隠すと残った行の節が消える。
// 全行に節の欄を持たせてあり (先頭以外は hidden)、絞り込み中は
// まとめを解いて1行ずつ出す。
(function () {
  var bar = document.querySelector('.aff-filter');
  if (!bar) return;

  var input = document.getElementById('aff-q');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var tradeEl = document.getElementById('aff-trade');
  var jump = document.querySelector('.affinity-jump');
  var tables = [].slice.call(document.querySelectorAll('.affinity-table'));
  if (!tables.length) return;

  bar.hidden = false;

  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  var groups = tables.map(function (table) {
    var wrap = table.closest('.aff-table-wrap') || table;
    var head = wrap.previousElementSibling;
    while (head && head.tagName !== 'H2') head = head.previousElementSibling;

    var rows = [].slice.call(table.querySelectorAll('tr')).filter(function (tr) {
      return tr.querySelector('td');
    });
    rows.forEach(function (tr) {
      tr._hay = norm(tr.textContent);
      var others = tr.querySelector('.aff-others');
      tr._trade = !!(others && others.textContent.trim());
      var place = tr.querySelector('.aff-place');
      tr._place = place;
      tr._span = place ? place.getAttribute('rowspan') : null;
      tr._leader = !!(place && !place.hidden);
    });
    return { head: head, wrap: wrap, rows: rows, name: norm(head ? head.textContent : ''), id: head ? head.id : null };
  });

  var total = groups.reduce(function (n, g) { return n + g.rows.length; }, 0);

  var navItems = jump ? [].slice.call(jump.querySelectorAll('li')).map(function (li) {
    var a = li.querySelector('a');
    var num = a ? a.querySelector('span') : null;
    return { li: li, num: num, total: num ? num.textContent : '', id: a ? a.getAttribute('href').slice(1) : null };
  }) : [];

  // 節のまとめを解く / 戻す。
  function ungroup(g) {
    g.rows.forEach(function (tr) {
      if (!tr._place) return;
      tr._place.hidden = tr.hidden;
      tr._place.setAttribute('rowspan', '1');
    });
  }

  function regroup(g) {
    g.rows.forEach(function (tr) {
      if (!tr._place) return;
      tr._place.hidden = !tr._leader;
      if (tr._span) tr._place.setAttribute('rowspan', tr._span);
      else tr._place.removeAttribute('rowspan');
    });
  }

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var tradeOnly = tradeEl && tradeEl.checked;
    var filtering = terms.length > 0 || tradeOnly;
    var shown = 0;
    var hitsById = {};

    groups.forEach(function (g) {
      // 人物名が当たっているときは、その人の行を丸ごと残す。
      var nameHit = terms.length > 0 && terms.every(function (t) { return g.name.indexOf(t) !== -1; });
      var hits = 0;

      g.rows.forEach(function (tr) {
        var ok = true;
        if (tradeOnly) ok = tr._trade;
        if (ok && terms.length && !nameHit) {
          for (var i = 0; i < terms.length; i++) {
            if (tr._hay.indexOf(terms[i]) === -1) { ok = false; break; }
          }
        }
        tr.hidden = filtering && !ok;
        if (!tr.hidden) hits++;
      });

      if (filtering) ungroup(g); else regroup(g);

      var show = !filtering || hits > 0;
      g.wrap.hidden = !show;
      if (g.head) g.head.hidden = !show;
      if (show) {
        shown += hits;
        if (g.id) hitsById[g.id] = hits;
      }
    });

    navItems.forEach(function (n) {
      var hit = n.id ? hitsById[n.id] : undefined;
      n.li.hidden = filtering && hit === undefined;
      if (n.num) n.num.textContent = filtering && hit !== undefined ? hit : n.total;
    });

    bar.classList.toggle('is-filtering', filtering);
    if (countEl) {
      countEl.textContent = filtering
        ? (shown === 0 ? refEmpty(bar) : total + '件中 ' + shown + '件')
        : total + '件';
    }

    if (window.history && history.replaceState) {
      var p = new URLSearchParams();
      if (input.value.trim()) p.set('q', input.value.trim());
      if (tradeOnly) p.set('trade', '1');
      var s = p.toString();
      history.replaceState(null, '', (s ? '?' + s : location.pathname) + location.hash);
    }
  }

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(apply, 80);
  });
  if (tradeEl) tradeEl.addEventListener('change', apply);

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      if (tradeEl) tradeEl.checked = false;
      apply();
      input.focus();
    });
  }

  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('q')) input.value = p.get('q');
    if (tradeEl && p.get('trade') === '1') tradeEl.checked = true;
  })();

  apply();
})();

// ポケモン個別ページの切り替え。
//
// 姿 (ふつう / アローラ / メガ) と、わざの種類 (レベル / わざマシン / 教え技…) の
// 2種類がある。どちらも中身は最初から HTML に入っていて、表示を入れ替えるだけ。
// ページを跨いで持ち回る状態は無いので、保存はしない。
(function () {
  var forms = document.querySelectorAll('.md-form');
  var tabs = document.querySelectorAll('.md-tab');
  if (!forms.length && !tabs.length) return;

  forms.forEach(function (button) {
    button.addEventListener('click', function () {
      forms.forEach(function (other) { other.classList.toggle('is-on', other === button); });
      // 節は姿ごとに分かれているとは限らない。中身が同じ姿はまとめてあり、
      // data-forms にその姿の番号が並んでいる。
      document.querySelectorAll('.md-part').forEach(function (part) {
        var forms = (part.dataset.forms || '').split(' ');
        part.classList.toggle('is-on', forms.indexOf(button.dataset.form) !== -1);
      });
      // 見出しのバトル絵も姿に合わせて差し替える。
      document.querySelectorAll('.md-hero-img').forEach(function (img) {
        img.classList.toggle('is-on', img.dataset.formArt === button.dataset.form);
      });
    });
  });

  tabs.forEach(function (button) {
    button.addEventListener('click', function () {
      // 姿ごとに同じ組が並ぶので、押された側の節の中だけを入れ替える。
      var scope = button.closest('.md-sec');
      if (!scope) return;
      scope.querySelectorAll('.md-tab').forEach(function (other) {
        other.classList.toggle('is-on', other === button);
      });
      scope.querySelectorAll('.md-panel').forEach(function (panel) {
        panel.classList.toggle('is-on', panel.dataset.panel === button.dataset.tab);
      });
      var card = button.closest('.md-card');
      if (card && card._mvApply) card._mvApply();
    });
  });
})();


// 覚えるわざをタイプで絞る。
//
// 1匹が覚えるわざは60本を超えることがある。「でんきわざは何を覚えるのか」を
// 探すのに6つのタブを目で舐めることになるので、タイプで絞れるようにする。
//
// 選べるのは1種類だけ。押すたびに切り替わり、同じ札をもう一度押すと外れる。
// 条件はタブを跨いで続く (タブを変えても絞ったまま)。
(function () {
  document.querySelectorAll('.md-card .md-mv-filter').forEach(function (bar) {
    var card = bar.closest('.md-card');
    var panels = [].slice.call(card.querySelectorAll('.md-panel'));
    if (!panels.length) return;

    var chips = [].slice.call(bar.querySelectorAll('.ref-chip'));
    var resetEl = bar.querySelector('.ref-reset');
    var countEl = bar.querySelector('.ref-count');
    var picked = null;

    bar.hidden = false;

    function rowsOf(panel) {
      if (!panel._rows) panel._rows = [].slice.call(panel.querySelectorAll('tbody tr'));
      return panel._rows;
    }

    function apply() {
      panels.forEach(function (panel) {
        var shown = 0;
        rowsOf(panel).forEach(function (tr) {
          var ok = !picked || tr.dataset.type === picked;
          tr.hidden = !ok;
          if (ok) shown++;
        });

        // タブの数字は、いま出ている行数に合わせる。どのタブに残って
        // いるかが、開かなくても分かる。
        var tab = card.querySelector('.md-tab[data-tab="' + panel.dataset.panel + '"] span');
        if (tab) tab.textContent = shown;

        var note = panel.querySelector('.md-mv-empty');
        if (!shown) {
          if (!note) {
            note = document.createElement('p');
            note.className = 'md-mv-empty md-empty';
            note.textContent = refEmpty(bar);
            panel.appendChild(note);
          }
          note.hidden = false;
        } else if (note) {
          note.hidden = true;
        }
      });

      // 札の数字は、開いているタブに何本あるか。絞っている最中も
      // 「他のタイプなら何本あるか」が読める。
      var active = card.querySelector('.md-panel.is-on') || panels[0];
      var byType = {};
      rowsOf(active).forEach(function (tr) {
        byType[tr.dataset.type] = (byType[tr.dataset.type] || 0) + 1;
      });
      chips.forEach(function (chip) {
        var n = byType[chip.dataset.value] || 0;
        var span = chip.querySelector('span');
        if (span) span.textContent = n;
        chip.classList.toggle('is-off', n === 0);
      });

      if (countEl) {
        var total = rowsOf(active).length;
        var shownActive = rowsOf(active).filter(function (tr) { return !tr.hidden; }).length;
        countEl.textContent = picked ? shownActive + ' / ' + total : '';
      }
    }

    card._mvApply = apply;

    function select(value) {
      picked = value;
      chips.forEach(function (chip) {
        var on = chip.dataset.value === picked;
        chip.classList.toggle('is-on', on);
        chip.setAttribute('aria-pressed', on ? 'true' : 'false');
      });
      apply();
    }

    chips.forEach(function (chip) {
      chip.addEventListener('click', function () {
        select(picked === chip.dataset.value ? null : chip.dataset.value);
      });
    });

    if (resetEl) resetEl.addEventListener('click', function () { select(null); });

    apply();
  });
})();

// ポケモン図鑑 (/reborn/mon/) の絞り込み。
//
// 807種を1枚に並べてある。操作子は hidden 付きで書き出してあり、ここで外す。
// JavaScript を切っていても一覧はそのまま残り、Ctrl+F は今までどおり効く。
(function () {
  var bar = document.querySelector('.mi-filter');
  var grid = document.querySelector('.mi-grid');
  if (!bar || !grid) return;

  var input = document.getElementById('mi-q');
  var wildEl = document.getElementById('mi-wild');
  var countEl = bar.querySelector('.ref-count');
  var resetEl = bar.querySelector('.ref-reset');
  var cards = [].slice.call(grid.querySelectorAll('.mi-card'));
  if (!cards.length) return;

  bar.hidden = false;

  // ひらがなで打っても片仮名の種族名に当たるようにする。
  function norm(s) {
    return (s || '').normalize('NFKC').toLowerCase()
      .replace(/[ぁ-ゖ]/g, function (c) {
        return String.fromCharCode(c.charCodeAt(0) + 0x60);
      });
  }

  cards.forEach(function (card) {
    card._hay = norm((card.getAttribute('data-name') || '') + ' ' + (card.getAttribute('data-en') || ''));
    card._types = (card.getAttribute('data-types') || '').split(' ');
    card._wild = card.getAttribute('data-wild') === '1';
  });

  var picked = [];

  function apply() {
    var terms = norm(input.value.trim());
    terms = terms ? terms.split(/\s+/) : [];
    var wildOnly = wildEl && wildEl.checked;
    var shown = 0;

    cards.forEach(function (card) {
      var ok = true;
      if (picked.length) {
        ok = false;
        for (var i = 0; i < picked.length; i++) {
          if (card._types.indexOf(picked[i]) !== -1) { ok = true; break; }
        }
      }
      if (ok && wildOnly) ok = card._wild;
      if (ok && terms.length) {
        ok = terms.every(function (t) { return card._hay.indexOf(t) !== -1; });
      }
      card.hidden = !ok;
      if (ok) shown++;
    });

    if (countEl) {
      countEl.textContent = shown === cards.length ? '' : shown + ' / ' + cards.length;
    }
    save(terms.length || picked.length || wildOnly);
  }

  // 絞った状態を URL に残す。人に渡せるようにするため。
  function save(filtering) {
    if (!window.history || !history.replaceState) return;
    var p = new URLSearchParams();
    if (input.value.trim()) p.set('q', input.value.trim());
    if (picked.length) p.set('t', picked.join(','));
    if (wildEl && wildEl.checked) p.set('wild', '1');
    var s = p.toString();
    history.replaceState(null, '', (filtering && s ? '?' + s : location.pathname) + location.hash);
  }

  input.addEventListener('input', apply);
  if (wildEl) wildEl.addEventListener('change', apply);

  bar.querySelectorAll('.ref-chip').forEach(function (chip) {
    chip.addEventListener('click', function () {
      var value = chip.getAttribute('data-value');
      var at = picked.indexOf(value);
      if (at === -1) picked.push(value); else picked.splice(at, 1);
      chip.classList.toggle('is-on', at === -1);
      chip.setAttribute('aria-pressed', at === -1 ? 'true' : 'false');
      apply();
    });
  });

  if (resetEl) {
    resetEl.addEventListener('click', function () {
      input.value = '';
      picked = [];
      bar.querySelectorAll('.ref-chip').forEach(function (chip) {
        chip.classList.remove('is-on');
        chip.setAttribute('aria-pressed', 'false');
      });
      if (wildEl) wildEl.checked = false;
      apply();
      input.focus();
    });
  }

  // 「/」で検索欄へ。入力中は邪魔しない。
  document.addEventListener('keydown', function (ev) {
    if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    var t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });

  // 共有された URL の条件を復元する。
  (function restore() {
    var p = new URLSearchParams(location.search);
    if (p.get('q')) input.value = p.get('q');
    if (p.get('wild') === '1' && wildEl) wildEl.checked = true;
    if (p.get('t')) {
      p.get('t').split(',').forEach(function (value) {
        var chip = bar.querySelector('.ref-chip[data-value="' + value + '"]');
        if (!chip) return;
        picked.push(value);
        chip.classList.add('is-on');
        chip.setAttribute('aria-pressed', 'true');
      });
    }
  })();

  apply();
})();
