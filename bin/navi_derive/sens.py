"""章 n の仮の状態で、確かでない事実を1つずつ反転させ、大ホールから行ける範囲が変わるものを拾う。"""
import json, pickle, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import navi_engine as ne, states
n = int(sys.argv[1])
hub = tuple(int(v) for v in sys.argv[2].split(',')) if len(sys.argv) > 2 else (29, 34, 46)
c2 = pickle.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'choke2.pkl'), 'rb'))
where = {}
for s, evs in c2['sw'].items(): where[('S', s)] = {m for m, e in evs}
for v, evs in c2['var'].items(): where[('V', v)] = {m for m, e in evs}
for m, e in c2['self']:
    for ch in 'ABCD': where[('SS', m, e, ch)] = {m}

def fingerprint(S):
    W = ne.World(S)
    prev = ne.explore(W, ne.node(*hub))
    return {s[0] for s in prev}, len(prev)

t = time.time()
base = states.make_state(n)
maps0, cnt0 = fingerprint(base)
hits = []
for f, row in states.TABLE.items():
    v, sure = row[n]
    if sure != 'unsure': continue
    if not (where.get(f, set()) & maps0): continue
    flip = (not v) if not isinstance(v, int) or isinstance(v, bool) else (0 if v else 1)
    S = states.make_state(n, {f: flip})
    maps1, cnt1 = fingerprint(S)
    if maps1 != maps0 or abs(cnt1 - cnt0) > 0:
        hits.append({'fact': repr(f), 'value': v, 'gain': sorted(maps1 - maps0), 'lose': sorted(maps0 - maps1), 'dcnt': cnt1 - cnt0})
json.dump({'n': n, 'maps': len(maps0), 'hits': hits}, open(f'sens_{n}.json', 'w'), ensure_ascii=False)
print(n, 'base maps', len(maps0), 'sensitive', len(hits), f'{time.time() - t:.0f}s', flush=True)
