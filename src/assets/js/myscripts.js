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


$(document).ready(function () {
  // Enables images to open into new tab on click
  $("img.tabImage").each(function () {
    $(this).attr("onclick", "window.open(this.src, '_blank');")
  });

  // Enables spoiler buttons
  $('.spoilerBtn').click(function() {
    $(this).parent().find('.spoilerText').css('display', 'block');
    $(this).hide();
  })

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
