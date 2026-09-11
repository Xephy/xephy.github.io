---
title: ナビ（β版）
permalink: /reborn/navi/
description: "ポケモンリボーンで、出発地から目的地まで歩いて行く道を地図で案内します。進み具合ごとに通れる道で探します。"
---

<p id="title-text">ナビ（β版）</p>

<p class="ref-back"><a href="/reborn/">目次へ戻る</a></p>

出発地と目的地を選ぶと、歩いて行く道を地図で案内します。通れる道は物語の進み具合で変わるので、何章まで進めたかも選んでください。

出発地と目的地は、その場所のポケモンセンターの前です。ポケモンセンターの無い場所は、その場所の入口にしています。空を飛ぶ・ロッククライム・かいりき・ダイビングを使う道は案内しません。14章以外の進み具合は、ゲームのデータと本文から組み立てたものです。

<div class="navi" id="navi" data-base="/assets/navi/" data-default="ch1">
<div class="navi-panel">
<div class="navi-form">
<label class="navi-field"><span>進み具合</span><select id="navi-prog"><option value="ch1" data-badges="1">1章まで終えた</option><option value="ch2" data-badges="2">2章まで終えた</option><option value="ch3" data-badges="2">3章まで終えた</option><option value="ch4" data-badges="3">4章まで終えた</option><option value="ch5" data-badges="4">5章まで終えた</option><option value="ch6" data-badges="4">6章まで終えた</option><option value="ch7" data-badges="5">7章まで終えた</option><option value="ch8" data-badges="6">8章まで終えた</option><option value="ch9" data-badges="7">9章まで終えた</option><option value="ch10" data-badges="8">10章まで終えた</option><option value="ch11" data-badges="9">11章まで終えた</option><option value="ch12" data-badges="10">12章まで終えた</option><option value="ch13" data-badges="11">13章まで終えた</option><option value="ch14" data-badges="12">14章まで終えた</option><option value="ch15" data-badges="13">15章まで終えた</option><option value="ch16" data-badges="14">16章まで終えた</option><option value="ch17" data-badges="16">17章まで終えた</option><option value="ch18" data-badges="17">18章まで終えた</option><option value="ch19" data-badges="18">19章まで終えた</option></select></label>
<label class="navi-field navi-from"><span>出発地</span><select id="navi-from" disabled><option>読み込み中…</option></select></label>
<label class="navi-field navi-to"><span>目的地</span><select id="navi-to" disabled><option>読み込み中…</option></select></label>
<div class="navi-row"><button type="button" id="navi-swap" class="navi-swap" title="出発地と目的地を入れ替える">⇅ 入れ替え</button><button type="button" id="navi-go" class="navi-go">ナビ開始</button></div>
<p class="navi-msg" id="navi-msg" role="status"></p>
</div>
<div class="navi-summary" id="navi-summary" hidden></div>
<ol class="navi-steps" id="navi-steps"></ol>
</div>
<div class="navi-map" id="navi-map">
<div class="navi-hint" id="navi-hint">ここに地図と道筋が出ます</div>
<div class="navi-stage" id="navi-stage"><div class="navi-world" id="navi-world"></div></div>
<div class="navi-banner" id="navi-banner" hidden></div>
<div class="navi-mapname" id="navi-mapname" hidden></div>
<div class="navi-stepnav" id="navi-stepnav" hidden><button type="button" id="navi-prev">前へ</button><button type="button" id="navi-next" class="is-primary">次へ</button></div>
<div class="navi-ctrl"><button type="button" id="navi-zin" aria-label="拡大">＋</button><button type="button" id="navi-zout" aria-label="縮小">－</button><button type="button" id="navi-fit" aria-label="いまの区間に合わせる">◎</button></div>
</div>
</div>

<script src="/assets/js/navi.js" defer></script>