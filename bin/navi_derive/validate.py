"""章 n の状態で、その章の本文の見出しに出てくる場所へ行けるか。"""
import os
import sys, re, importlib.machinery, importlib.util
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import navi_engine as ne, states
l = importlib.machinery.SourceFileLoader('nb', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'navi-build'))
sp = importlib.util.spec_from_loader('nb', l); nb = importlib.util.module_from_spec(sp); l.exec_module(nb)
meta = nb.metadata()
W_ = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src', 'reborn-chapters')
for n in [int(a) for a in sys.argv[1:]]:
    S = states.make_state(n); W = ne.World(S)
    pl = nb.places(meta)
    for p in pl: p['live'] = [m for m in p['maps'] if nb.live(meta, S, m)]
    where = {m: p['ja'] for p in pl for m in p['live']}
    hub = (519, 35, 46) if 479 in S.switches else (29, 34, 46)
    prev = ne.explore(W, ne.node(*hub))
    got = {where[s[0]] for s in prev if s[0] in where}
    heads = re.findall(r'^## (.*?)(?: \{#.*)?$', open(f'{W_}/episode-{n}.md', encoding='utf-8').read(), re.M)
    names = {p['ja'] for p in pl}
    want = {nm for h in heads for nm in names if nm in h.replace('ネオ', '')}
    miss = sorted(want - got)
    print(n, 'badges', S.badges, 'reach', len(got), 'heading places', len(want), 'missing:', ' / '.join(miss) if miss else '-', flush=True)
