"""自分スイッチ・変数・スイッチで形が変わるイベントのうち、道の要所をふさぐ/扉の行き先を変えるもの。"""
import collections, pickle, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import navi_engine as ne
from navi_engine import D, st
S = ne.State.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '_ja', 'navi', 'states', 'ch14.json'))
W = ne.World(S)

def shape(p):
    p = D(p)
    if ne.removable(p): return (False, ())
    g = D(p['@graphic'])
    block = (not p.get('@through', False)) and bool(g.get('@character_name') or g.get('@tile_id'))
    doors = tuple(sorted({tuple(D(c)['@parameters'][1:4]) for c in p['@list'] if D(c)['@code'] == 201 and D(c)['@parameters'][0] == 0})) if p['@trigger'] in (0, 1, 2) else ()
    return (block, doors)

def portals(L, mid):
    out = set()
    for (x, y) in L.warps():
        for dx, dy in ne.DIRS.values():
            if L.valid(x + dx, y + dy): out.add((x + dx, y + dy))
    for other, dx, dy in W.conns.get(mid, []):
        O = W.get(other)
        if not O: continue
        for x in range(L.xs):
            for y in (0, L.ys - 1):
                if O.valid(x + dx, y + dy): out.add((x, y))
        for y in range(L.ys):
            for x in (0, L.xs - 1):
                if O.valid(x + dx, y + dy): out.add((x, y))
    return out

def comps(L, blocked):
    lab = {}; n = 0
    for sx in range(L.xs):
        for sy in range(L.ys):
            if (sx, sy) in lab or (sx, sy) in blocked: continue
            n += 1; q = [(sx, sy)]; lab[(sx, sy)] = n
            while q:
                x, y = q.pop()
                for d, (dx, dy) in ne.DIRS.items():
                    nx, ny = x + dx, y + dy
                    if not L.valid(nx, ny) or (nx, ny) in lab or (nx, ny) in blocked: continue
                    if L.passable(x, y, d) and L.passable(nx, ny, 10 - d):
                        lab[(nx, ny)] = n; q.append((nx, ny))
    return lab

def partition(lab, ps):
    return frozenset(frozenset(p for p in ps if lab.get(p) == c) for c in {lab.get(p) for p in ps})

res = {'self': [], 'var': collections.defaultdict(list), 'sw': collections.defaultdict(list)}
for mid in ne.INFOS:
    m = ne.load_map(mid)
    if m is None: continue
    L = W.get(mid)
    # 事実ごとに、その値でページの形が変わるイベントをまとめる (横に並んだ番人や壁は、まとめて外さないと効かない)
    groups = collections.defaultdict(list)
    for e in (D(x) for x in (m['@events'] or {}).values()):
        pages = [D(x) for x in e['@pages']]
        shapes = [shape(p) for p in pages]
        if len(set(shapes)) < 2: continue
        keys = set()
        for p in pages:
            c = D(p['@condition'])
            if c.get('@self_switch_valid'): keys.add(('SS', e['@id']))
            if c.get('@variable_valid') and c['@variable_id'] not in ne.STORY_VARS: keys.add(('V', c['@variable_id']))
            for k in ('1', '2'):
                if c.get(f'@switch{k}_valid'): keys.add(('S', c[f'@switch{k}_id']))
        for k in keys:
            groups[k].append((e, shapes))
    if not groups: continue
    ps = portals(L, mid)
    if len(ps) < 2: continue
    saved = L.ev_at; L.ev_at = collections.defaultdict(list)
    base = comps(L, set())
    for k, evs in groups.items():
        doorchange = any(len({s[1] for s in sh}) > 1 for e, sh in evs)
        tiles = {(e['@x'], e['@y']) for e, sh in evs if any(s[0] for s in sh)}
        choke = False
        if tiles:
            lab = comps(L, tiles)
            choke = partition(lab, ps - tiles) != partition(base, ps - tiles)
        if not (doorchange or choke): continue
        if k[0] == 'SS':
            res['self'].append((mid, k[1]))
        elif k[0] == 'V':
            res['var'][k[1]].append(mid)
        else:
            res['sw'][k[1]].append(mid)
    L.ev_at = saved
print('self-switch events', len(res['self']))
print('variables', len(res['var']), [(v, ne.VAR_NAMES[v]) for v in list(res['var'])[:30]])
print('switches', len(res['sw']))
pickle.dump({'self': res['self'], 'var': {k: [(m, 0) for m in v] for k, v in res['var'].items()}, 'sw': {k: [(m, 0) for m in v] for k, v in res['sw'].items()}}, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'choke2.pkl'), 'wb'))
