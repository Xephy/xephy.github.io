"""章ごとの進み具合を、14章のセーブを軸にゲームのデータから組み立てる (1回目: 規則だけ)。

事実 (fact) の種類:
  ('S', id)              スイッチ
  ('SS', map, ev, ch)    セルフスイッチ
  ('V', id)              変数
  ('I', symbol)          大事なもの
道に効くものだけを章ごとに決め、ほかは14章のセーブの値のまま (道に効かないので)。

各事実を書き換えるイベント (setter) に「何章の出来事か」の見積もりをつける:
  そのページで物語変数 E<k> を書く → k 章 (exact)
  条件に E<k> がある / 条件のスイッチが立つ章 → その章以降 (lower)
  地図が攻略本文に初めて出てくる章 → その章以降 (map)
"""
import collections
import json
import os
import pickle
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import navi_engine as ne  # noqa: E402
from navi_engine import D, st  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SAVE14 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '_ja', 'navi', 'states', 'ch14.json')
ST = {i: int(re.match(r'E(\d+)', n).group(1)) for i, n in enumerate(ne.VAR_NAMES) if re.match(r'E\d+ Story', n)}
STVAR = {k: i for i, k in ST.items()}
FINAL = {15: 40, 16: 65, 17: 21, 18: 61, 19: 145}     # max(代入, 条件) を実測
# 章の終わりのバッジの数 (バッジを渡すイベントの物語変数から)
BADGES = {1: 1, 2: 2, 3: 2, 4: 3, 5: 4, 6: 4, 7: 5, 8: 6, 9: 7, 10: 8, 11: 9, 12: 10, 13: 11,
          14: 12, 15: 13, 16: 14, 17: 16, 18: 17, 19: 18}
NEXT_START = {2: 1}    # 2章の最後 (キャノピーバッジ) のイベントが E3 を 1 にする

MC = json.load(open(os.path.join(HERE, 'map_chapters_all.json')))


def map_first(mid):
    chs = [c for c in (MC.get(ne.map_name(mid)) or []) if c < 100]
    return min(chs) if chs else None


def scan():
    """事実ごとの setter: [{'val', 'map', 'ev', 'story', 'lower', 'dep', 'mf'}]"""
    out = collections.defaultdict(list)

    def add(key, val, mid, eid, pg, stack, lst):
        story = [ST[c['@parameters'][0]] for c in lst if c['@code'] == 122 and c['@parameters'][0] in ST
                 and c['@parameters'][2] == 0 and c['@parameters'][3] == 0]
        lower, dep = [], []
        cond = D(pg['@condition']) if pg.get('@condition') is not None else {}
        if cond.get('@variable_valid') and cond['@variable_id'] in ST:
            lower.append(ST[cond['@variable_id']])
        for k in ('1', '2'):
            if cond.get(f'@switch{k}_valid'):
                dep.append(cond[f'@switch{k}_id'])
        for q, truth in stack:
            if q[0] == 1 and q[1] in ST and truth and q[2] == 0 and q[4] in (0, 1, 3):
                lower.append(ST[q[1]])
            if q[0] == 0 and truth == (q[2] == 0):
                dep.append(q[1])
        out[key].append({'val': val, 'map': mid, 'ev': eid, 'story': story, 'lower': lower, 'dep': dep,
                         'mf': map_first(mid) if isinstance(mid, int) else None})

    def run(mid, eid, pg, lst):
        stack = []
        for c in lst:
            code, ind, q = c['@code'], c['@indent'], c['@parameters']
            if code == 411:
                for s_ in stack:
                    if s_[0] == ind:
                        s_[2] = not s_[2]
                continue
            stack = [s_ for s_ in stack if s_[0] < ind]
            if code == 111:
                stack.append([ind, q, True])
            sk = [(s_[1], s_[2]) for s_ in stack]
            if code == 121:
                for i in range(q[0], q[1] + 1):
                    add(('S', i), q[2] == 0, mid, eid, pg, sk, lst)
            elif code == 122 and q[2] == 0 and q[3] == 0:
                for i in range(q[0], q[1] + 1):
                    if i not in ST:
                        add(('V', i), q[4], mid, eid, pg, sk, lst)
            elif code == 123 and isinstance(mid, int):
                add(('SS', mid, eid, st(q[0])), q[1] == 0, mid, eid, pg, sk, lst)
            elif code in (355, 655):
                t = st(q[0])
                for sym in re.findall(r'pbReceiveItem\(:(\w+)', t) + re.findall(r'pbStoreItem\(:(\w+)', t):
                    add(('I', sym), True, mid, eid, pg, sk, lst)
                for sym in re.findall(r'pbDeleteItem\(:(\w+)', t):
                    add(('I', sym), False, mid, eid, pg, sk, lst)
                for ev2, ch2, v2 in re.findall(r'pbSetSelfSwitch\((\d+),\s*["\'](\w)["\'],\s*(true|false)', t):
                    if isinstance(mid, int):
                        add(('SS', mid, int(ev2), ch2), v2 == 'true', mid, eid, pg, sk, lst)

    for mid in ne.INFOS:
        m = ne.load_map(mid)
        if m is None or ne.map_name(mid) == 'REMOVED':
            continue
        for e in (D(x) for x in (m['@events'] or {}).values()):
            for pg in e['@pages']:
                pg = D(pg)
                run(mid, e['@id'], pg, [D(c) for c in pg['@list']])
    for ce in ne.rmarshal.load(f'{ne.GAME}/Data/CommonEvents.rxdata'):
        if ce:
            ce = D(ce)
            run('common', ce['@id'], {'@condition': None}, [D(c) for c in ce['@list']])
    return out


def chapter_of(s, when_on):
    """setter の章の見積もり。(章, 種類)。"""
    if s['story']:
        return max(s['story']), 'exact'
    cand = list(s['lower'])
    for d in s['dep']:
        if d in when_on and when_on[d]:
            cand.append(when_on[d])
    if s['mf']:
        cand.append(s['mf'])
    if not cand:
        return None, None
    return max(cand), ('lower' if s['lower'] or any(d in when_on for d in s['dep']) else 'map')


def relevant():
    """道に効くもの (choke2.pkl) に加えて、どこかのイベントの条件に出るものすべて。
    道に効かないものも規則の値にしておく (14章より後に変わるものを取りこぼさないため)。"""
    c2 = pickle.load(open(os.path.join(HERE, 'choke2.pkl'), 'rb'))
    facts = {('S', s) for s in c2['sw']} | {('V', v) for v in c2['var']}
    for mid, eid in c2['self']:
        for ch in 'ABCD':
            facts.add(('SS', mid, eid, ch))
    for mid in ne.INFOS:
        m = ne.load_map(mid)
        if m is None:
            continue
        for e in (D(x) for x in (m['@events'] or {}).values()):
            for pg in e['@pages']:
                c = D(D(pg)['@condition'])
                for k in ('1', '2'):
                    if c.get(f'@switch{k}_valid'):
                        facts.add(('S', c[f'@switch{k}_id']))
                if c.get('@variable_valid') and c['@variable_id'] not in ST:
                    facts.add(('V', c['@variable_id']))
                for cm in (D(x) for x in D(pg)['@list']):
                    q = cm['@parameters']
                    if cm['@code'] == 111 and q[0] == 0:
                        facts.add(('S', q[1]))
                    elif cm['@code'] == 111 and q[0] == 1 and q[1] not in ST:
                        facts.add(('V', q[1]))
                    elif cm['@code'] == 111 and q[0] == 12:
                        for sym in re.findall(r'pbQuantity\(:(\w+)\)', st(q[1])):
                            if sym in ne.KEY_ITEMS:
                                facts.add(('I', sym))
    return facts


def default(fact):
    return 0 if fact[0] == 'V' else False


def value_at(fact, setters, save_val, n, when_on):
    """n 章の終わりの値と、確かさ ('save' / 'rule' / 'default' / 'unsure')。"""
    if n == 14:
        return save_val, 'save'
    es = []
    for s in setters:
        c, kind = chapter_of(s, when_on)
        es.append((c, kind, s['val']))
    known = [e for e in es if e[0] is not None]
    unknown = [e for e in es if e[0] is None]
    if n < 14:
        past = [e for e in known if e[0] <= n]
        if not past:
            v = default(fact)
            sure = 'default' if not unknown else 'unsure'
            # 14章で既定の値と違うのに、それより前に起きたと分かる setter が無い → 見積もりが要る
            if save_val != v and not any(e[0] <= 14 for e in known):
                sure = 'unsure'
            return v, sure
        top = max(e[0] for e in past)
        vals = {e[2] for e in past if e[0] == top}
        if len(vals) == 1:
            v = vals.pop()
            # そのあと14章までに書き換える setter が無いのに、14章の値と違うなら怪しい
            later = [e for e in known if n < e[0] <= 14]
            if not later and v != save_val:
                return save_val, 'unsure'
            return v, 'rule' if not unknown else 'unsure'
        return save_val, 'unsure'
    # 15章以降: 14章の値から、15〜n 章の setter を当てる
    fut = [e for e in known if 14 < e[0] <= n]
    if not fut:
        return save_val, 'rule' if not unknown else 'unsure'
    top = max(e[0] for e in fut)
    vals = {e[2] for e in fut if e[0] == top}
    if len(vals) == 1:
        return vals.pop(), 'rule' if not unknown else 'unsure'
    return save_val, 'unsure'


def main():
    save = ne.State.load(SAVE14)
    setters = scan()
    facts = relevant()
    # スイッチが立つ章 (依存に使う): 14章で立っているものは、立てる setter の最小の章
    when_on = {}
    for _ in range(4):
        for f in facts:
            if f[0] != 'S':
                continue
            cs = [chapter_of(s, when_on)[0] for s in setters.get(f, []) if s['val']]
            cs = [c for c in cs if c]
            if cs:
                when_on[f[1]] = min(cs)

    def save_value(f):
        if f[0] == 'S':
            return f[1] in save.switches
        if f[0] == 'V':
            return save.var(f[1])
        if f[0] == 'SS':
            return (f[1], f[2], f[3]) in save.selfsw
        return f[1] in save.items

    table = {}
    unsure = collections.Counter()
    for f in sorted(facts, key=str):
        row = {}
        for n in range(1, 20):
            v, sure = value_at(f, setters.get(f, []), save_value(f), n, when_on)
            row[n] = (v, sure)
            if sure == 'unsure':
                unsure[n] += 1
        table[f] = row
    pickle.dump({'table': table, 'setters': dict(setters), 'when_on': when_on}, open(os.path.join(HERE, 'derive.pkl'), 'wb'))
    print('facts', len(facts))
    print('unsure per chapter', dict(sorted(unsure.items())))


if __name__ == '__main__':
    main()
