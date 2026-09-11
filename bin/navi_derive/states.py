"""derive.pkl (規則で決めた表) と判断の上書き (decisions.json) から、章ごとの State を作る。"""
import copy
import json
import os
import pickle  # 自分で書き出した derive.pkl を読むだけ
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import navi_engine as ne  # noqa: E402
import derive  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
D_ = pickle.load(open(os.path.join(HERE, 'derive.pkl'), 'rb'))
TABLE = D_['table']
DEC = os.path.join(HERE, 'decisions.json')
ITEMS = json.load(open(os.path.join(HERE, 'item_chapters.json'), encoding='utf-8'))


def decisions():
    """{fact(str): {章(str): 値}} 手で決めた値。"""
    if os.path.exists(DEC):
        return json.load(open(DEC, encoding='utf-8'))
    return {}


def make_state(n, override=None):
    base = ne.State.load(derive.SAVE14)
    s = copy.deepcopy(base)
    # 物語変数
    for k, vid in derive.STVAR.items():
        if k <= min(n, 14):
            val = base.var(vid)
        elif k <= n:
            val = derive.FINAL[k]
        elif k == n + 1 and n in derive.NEXT_START:
            val = derive.NEXT_START[n]
        else:
            val = 0
        if val:
            s.vars[vid] = val
        else:
            s.vars.pop(vid, None)
    s.badges = derive.BADGES[n]
    dec = decisions()
    for f, row in TABLE.items():
        v = row[n][0]
        d = dec.get(repr(f), {})
        if str(n) in d:
            v = d[str(n)]
        if override and f in override:
            v = override[f]
        if f[0] == 'S':
            (s.switches.add if v else s.switches.discard)(f[1])
        elif f[0] == 'V':
            if v:
                s.vars[f[1]] = v
            else:
                s.vars.pop(f[1], None)
        elif f[0] == 'SS':
            (s.selfsw.add if v else s.selfsw.discard)((f[1], f[2], f[3]))
        elif f[0] == 'I':
            (s.items.add if v else s.items.discard)(f[1])
    # 大事なもの: 攻略本文に初めて出てくる章から持っているものとする。
    # 14章より前は、14章のセーブで持っているものに限る (使って無くなるものがあるため)
    for sym, (_ja, chs) in ITEMS.items():
        first = min(chs) if chs else (11 if sym.startswith('CRYSTALPLUG') else None)
        if first is None:
            continue
        have = (sym in base.items) if n < 14 else (sym in base.items or first <= n)
        if n != 14:
            (s.items.add if have and first <= n else s.items.discard)(sym)
    return s
