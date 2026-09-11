"""ナビの道探し: ある時点の進行状況で、地図をまたいだ道を探す。

進行状況 (スイッチ・変数・セルフスイッチ・バッジ・持ち物) は、その時点のセーブデータから
bin/navi-state で書き出した _ja/navi/states/*.json を読む。
辿るもの:
  * 歩き・段差 (Game_Player / Game_Map#playerPassable? と同じ判定)
  * 波乗り (バッジ10) ・たきのぼり (バッジ12)
  * 場所移動イベント (扉・階段・地図の端)、移動ルートで主人公を動かすイベント
  * 地図のつながり (connections.dat)
  * 移動のときにイベントが切り替えるスイッチ・変数 (来た向きの記録など)。道の途中で
    変わった値を持ち歩き、その値でイベントのページを選び直す
  * 氷の上の滑り (pbSlideOnIce)・ベルトコンベア (pbConveyorMove)
扱わないもの: 空を飛ぶ・ロッククライム・かいりき
"""
import collections
import heapq
import itertools
import json
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, '..', 'Reborn-19.5.0-windows')
PATCH = os.path.join(ROOT, '..', 'reborn-19.5.43-ja', 'jp_translation')
JA = os.path.join(PATCH, 'work', 'src')
CACHE = os.path.join(ROOT, 'bin', '.navi-cache')
sys.path.insert(0, os.path.join(PATCH, 'tools'))
import rmarshal  # noqa: E402
DIRS = {2: (0, 1), 4: (-1, 0), 6: (1, 0), 8: (0, -1)}
# Scripts/Field.rb の PBTerrain
LEDGE, WATERFALL, CREST, ICE = 1, 8, 9, 12
SURFABLE = {5, 6, 7, 8, 9}          # pbIsSurfableTag? (滝も含む)
PASS_WATER = {5, 6, 7, 9}           # pbIsPassableWaterTag? (波乗り中に通れる)
CONVEYOR = {20: 2, 21: 4, 22: 6, 23: 8}   # ベルトコンベアのタグと、運ばれる向き
CANT_SURF = 850                     # SystemConstants の Cant_Surf
# Scripts/Reborn/Settings.rb
BADGE_ROCKSMASH, BADGE_SURF, BADGE_WATERFALL, BADGE_ROCKCLIMB = 3, 10, 12, 16


def st(x):
    return x.decode('utf-8', 'replace') if isinstance(x, bytes) else ('' if x is None else str(x))


def D(o):
    return o.data if hasattr(o, 'data') else o


def table(obj):
    raw = bytes(obj.data if hasattr(obj, 'data') else obj)
    _d, xs, ys, zs, n = struct.unpack('<5i', raw[:20])
    return xs, ys, zs, struct.unpack(f'<{n}h', raw[20:20 + 2 * n])


SYSTEM = rmarshal.load(f'{GAME}/Data/System.rxdata').data
SWITCH_NAMES = [st(n) for n in SYSTEM['@switches']]
VAR_NAMES = [st(n) for n in SYSTEM['@variables']]
STORY_VARS = {i for i, n in enumerate(VAR_NAMES) if re.match(r'E\d+ Story', n)}
TILESETS = rmarshal.load(f'{GAME}/Data/Tilesets.rxdata')
INFOS = rmarshal.load(f'{GAME}/Data/MapInfos.rxdata')
NAME_JA = {}
for _line in open(f'{JA}/20_map_names.jsonl', encoding='utf-8'):
    _r = json.loads(_line)
    NAME_JA[int(_r['key'])] = _r['ja']


def map_name(mid):
    return NAME_JA.get(mid) or st(D(INFOS[mid])['@name'])


_ITEMTEXT = open(os.path.join(GAME, 'Scripts', 'Reborn', 'itemtext.rb'), encoding='utf-8').read()
# 大事なもの (:keyitem)。条件分岐で持ち物を調べるもののうち、道に使ってよいのはこれだけ。
# 回復薬やあまいミツのような、人によって持っていたりいなかったりするものには頼らない
KEY_ITEMS = set(re.findall(r'\n  :(\w+) => \{[^}]*?:keyitem => true', _ITEMTEXT))

_MAPS = {}


def load_map(mid):
    if mid not in _MAPS:
        p = f'{GAME}/Data/Map{mid:03d}.rxdata'
        _MAPS[mid] = rmarshal.load(p).data if os.path.exists(p) else None
    return _MAPS[mid]


# ---------------------------------------------------------------- 進行状況

class State:
    """ある時点の進行状況。"""

    @classmethod
    def from_save(cls, save_path):
        o = {str(k): v for k, v in rmarshal.load(save_path).items()}
        first = lambda x: list(D(x).values())[0]  # noqa: E731
        self = cls()
        self.switches = {i for i, v in enumerate(first(o['switches'])) if v is True}
        self.vars = {i: v for i, v in enumerate(first(o['variable'])) if isinstance(v, int) and v}
        self.selfsw = {(k[0], k[1], st(k[2])) for k, v in first(o['self_switches']).items() if v}
        tr = D(o['Trainer'])
        self.badges = sum(1 for b in [v for k, v in tr.items() if 'badges' in str(k)][0] if b is True)
        g = D(o['PokemonGlobal'])
        self.partner = bool([v for k, v in g.items() if 'dependentEvents' in str(k)][0])
        bag = D(o['PokemonBag'])
        contents = [v for k, v in bag.items() if 'contents' in str(k)][0]
        self.items = {str(k).lstrip(':').strip("'") for k, v in D(contents).items() if v}
        self.visited = {i for i, v in enumerate(D([v for k, v in g.items() if 'visitedMaps' in str(k)][0])) if v}
        self.map_id = o['map_id']
        self.position = tuple(o['position'])
        return self

    @classmethod
    def load(cls, path):
        j = json.load(open(path, encoding='utf-8'))
        self = cls()
        self.switches = set(j['switches'])
        self.vars = {int(k): v for k, v in j['variables'].items()}
        self.selfsw = {tuple(x) for x in j['self_switches']}
        self.badges = j['badges']
        self.partner = j['partner']
        self.items = set(j['items'])
        self.visited = set(j.get('visited', []))
        self.map_id, self.position = j.get('map_id'), tuple(j.get('position') or ())
        return self

    def dump(self, path, label):
        """道探しに使うものだけを書き出す。持ち物は、条件分岐で調べられる大事なものだけ。"""
        need = set()
        for mid in INFOS:
            m = load_map(mid)
            for e in (D(x) for x in ((m or {}).get('@events') or {}).values()):
                for pg in e['@pages']:
                    for c in (D(x) for x in D(pg)['@list']):
                        if c['@code'] == 111 and c['@parameters'][0] == 12:
                            need.update(re.findall(r'pbQuantity\(:(\w+)\)', st(c['@parameters'][1])))
        j = {'label': label, 'badges': self.badges, 'partner': self.partner,
             'switches': sorted(self.switches), 'variables': {str(k): v for k, v in sorted(self.vars.items())},
             'self_switches': sorted(list(x) for x in self.selfsw),
             'items': sorted(self.items & need & KEY_ITEMS)}
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(j, f, ensure_ascii=False, indent=0)

    @property
    def can_surf(self):
        return self.badges >= BADGE_SURF and not self.partner and CANT_SURF not in self.switches

    @property
    def can_waterfall(self):
        return self.can_surf and self.badges >= BADGE_WATERFALL

    def switch(self, i):
        """None は分からない (s: で始まるスクリプトスイッチ)。"""
        if i < len(SWITCH_NAMES) and SWITCH_NAMES[i].startswith('s:'):
            return None
        return i in self.switches

    def var(self, i):
        return self.vars.get(i, 0)

    def selfswitch(self, mid, eid, ch):
        return (mid, eid, ch) in self.selfsw


class Overlay:
    """進行状況の一部 (道の途中で切り替わったスイッチ・変数) を差し替えたもの。"""
    def __init__(self, base, tog):
        self.base = base
        self.sw = {k[1]: v for k, v in tog if k[0] == 'S'}
        self.vr = {k[1]: v for k, v in tog if k[0] == 'V'}

    def switch(self, i):
        return self.sw[i] if i in self.sw else self.base.switch(i)

    def var(self, i):
        return self.vr[i] if i in self.vr else self.base.var(i)

    def __getattr__(self, k):
        return getattr(self.base, k)


def _toggle_keys():
    """移動のためのイベント (場所移動を含むか踏むと起きる、会話のないページ) が書き換えるスイッチ・変数と、
    書き換える値。物語の変数 (E# Story) と、どの条件にも出ないものは除く。"""
    os.makedirs(CACHE, exist_ok=True)
    cache = os.path.join(CACHE, 'toggles.json')
    if os.path.exists(cache):
        return {(k[0], k[1]): set(v) for k, v in json.load(open(cache))}
    keys = collections.defaultdict(set)
    talk_sw = collections.defaultdict(set)
    refs = set()     # どこかの条件 (ページの出現条件・条件分岐) に出るもの
    for mid in INFOS:
        m = load_map(mid)
        if m is None:
            continue
        for e in (D(x) for x in (m['@events'] or {}).values()):
            for pg in e['@pages']:
                pg = D(pg)
                c = D(pg['@condition'])
                for k in ('1', '2'):
                    if c.get(f'@switch{k}_valid'):
                        refs.add(('S', c[f'@switch{k}_id']))
                if c.get('@variable_valid'):
                    refs.add(('V', c['@variable_id']))
                for cm in (D(x) for x in pg['@list']):
                    if cm['@code'] == 111 and cm['@parameters'][0] in (0, 1):
                        refs.add(('S' if cm['@parameters'][0] == 0 else 'V', cm['@parameters'][1]))
                if pg['@trigger'] not in (0, 1, 2):
                    continue
                lst = [D(c) for c in pg['@list']]
                # 場所移動を含むページか、踏むと起きる (触れて起こす) ページ。どちらも会話のないもの。
                # 調べて起こす会話つきのページ (切符の販売機など) は、スイッチの値だけ別に集めておき、
                # 会話のないページでも書き換えられるスイッチに限って足す
                moves_ = any(c['@code'] == 201 for c in lst) or pg['@trigger'] in (1, 2)
                talk = any(c['@code'] in (101, 102) for c in lst)
                if talk and pg['@trigger'] == 0:
                    for c in lst:
                        q = c['@parameters']
                        if c['@code'] == 121:
                            for i in range(q[0], q[1] + 1):
                                talk_sw[('S', i)].add(q[2] == 0)
                    continue
                if not moves_ or talk:
                    continue
                for c in lst:
                    q = c['@parameters']
                    if c['@code'] == 121:
                        for i in range(q[0], q[1] + 1):
                            keys[('S', i)].add(q[2] == 0)
                    elif c['@code'] == 122 and q[2] == 0 and q[3] == 0:
                        for i in range(q[0], q[1] + 1):
                            if i not in STORY_VARS:
                                keys[('V', i)].add(q[4])
    for k, v in talk_sw.items():
        if k in keys:
            keys[k] |= v
    # 行き来で元に戻るものだけ: スイッチは ON にも OFF にもされるもの、変数は 0 に戻されるもの。
    # 物語やクエストの進み具合 (増えていくだけの値) を、道の途中の切り替えとして扱わないため
    keys = {k: v for k, v in keys.items()
            if k in refs and (v == {True, False} if k[0] == 'S' else (0 in v and len(v) >= 2))}
    json.dump([[list(k), sorted(v)] for k, v in sorted(keys.items())], open(cache, 'w'))
    return keys


TOGGLES = _toggle_keys()


# ---------------------------------------------------------------- イベントの読み取り

def page_ok(state, mid, eid, page):
    c = D(D(page)['@condition'])
    for k in ('1', '2'):
        if c.get(f'@switch{k}_valid'):
            if not state.switch(c[f'@switch{k}_id']):   # 分からないものは立っていないとみなす
                return False
    if c.get('@variable_valid') and state.var(c['@variable_id']) < c['@variable_value']:
        return False
    if c.get('@self_switch_valid') and not state.selfswitch(mid, eid, st(c['@self_switch_ch'])):
        return False
    return True


def eval_script(state, text, surf):
    """条件分岐のスクリプトのうち、進行状況から決まるもの。決まらなければ None。"""
    t = text.strip()
    if t == 'Kernel.pbRockClimb':
        return state.badges >= BADGE_ROCKCLIMB and not state.partner
    if t == 'Kernel.pbWaterfallDialogue':
        return state.can_waterfall
    if t == 'Kernel.pbRockSmash':
        return state.badges >= BADGE_ROCKSMASH
    if t in ('$PokemonGlobal.surfing == true', '$PokemonGlobal.surfing'):
        return surf
    if t == '!$PokemonGlobal.surfing':
        return not surf
    m = re.fullmatch(r'\$PokemonBag\.pbQuantity\(:(\w+)\)\s*>\s*0', t)
    if m:
        return (m.group(1) in state.items) if m.group(1) in KEY_ITEMS else None
    m = re.fullmatch(r'\$game_variables\[(\d+)\]\s*==\s*(-?\d+)', t)
    if m:
        return state.var(int(m.group(1))) == int(m.group(2))
    return None


def cond_111(state, mid, eid, p, facing=None, surf=False):
    """True / False / None (分からない)。facing は、イベントを起こしたときの主人公の向き。"""
    t = p[0]
    if t == 0:
        v = state.switch(p[1])
        return None if v is None else (v == (p[2] == 0))
    if t == 1:
        a = state.var(p[1])
        b = p[3] if p[2] == 0 else state.var(p[3])
        return [a == b, a >= b, a <= b, a > b, a < b, a != b][p[4]]
    if t == 2:
        return state.selfswitch(mid, eid, st(p[1])) == (p[2] == 0)
    if t == 6 and p[1] == -1 and facing:
        return facing == p[2]
    if t == 12:
        return eval_script(state, st(p[1]), surf)
    return None


def _talks(page):
    """会話・選択肢・トレーナー戦のあるページ (物語の場面)。"""
    for c in (D(x) for x in D(page)['@list']):
        if c['@code'] in (101, 102):
            return True
        if c['@code'] in (355, 111) and 'Battle' in str(c['@parameters']):
            return True
    return False


BADGE_CUT = 1


def removable(page, state=None):
    """いあいぎりの木・いわくだきの岩。その場で消せるので、道をふさがないものとする。
    state を渡したときは、そのわざを使えるバッジの数があるときだけ。"""
    s = ' '.join(str(D(c)['@parameters']) for c in D(page)['@list'])
    if 'pbCut' in s:
        return state is None or state.badges >= BADGE_CUT
    if 'pbRockSmash' in s:
        return state is None or state.badges >= BADGE_ROCKSMASH
    return False


# 移動ルートの命令 (RPG::MoveCommand) のうち、主人公の位置を変えるもの
MOVE_STEP = {1: (0, 1), 2: (-1, 0), 3: (1, 0), 4: (0, -1),
             5: (-1, 1), 6: (1, 1), 7: (-1, -1), 8: (1, -1)}
MOVE_HARMLESS = set(range(15, 46)) | {0}


def player_route(mr, facing):
    """移動ルートで主人公がどれだけ動くか。分からない命令があれば None。"""
    dx = dy = 0
    for c in (D(x) for x in D(mr)['@list']):
        code, q = c['@code'], c['@parameters']
        if code in MOVE_STEP:
            dx += MOVE_STEP[code][0]
            dy += MOVE_STEP[code][1]
        elif code in (12, 13) and facing:
            fx, fy = DIRS[facing]
            k = 1 if code == 12 else -1
            dx += fx * k
            dy += fy * k
        elif code == 14:
            dx += q[0]
            dy += q[1]
        elif code not in MOVE_HARMLESS:
            return None
    return dx, dy


def run_page(state, mid, eid, page, facing, surf=False):
    """ページを頭から読み、主人公がどこへ行くかを返す。

    [(行き先, 確か, 切り替え, 選択肢の文言)]。行き先は ('warp', 地図, x, y) か ('shift', dx, dy)。
    分岐の条件が分からないところは両方を辿り、確かでないとしるす。選択肢の枝は
    それぞれ別の行き先。切り替えは、道の途中で書き換わる TOGGLES の値。
    """
    out = []
    stack = []            # [indent, True/False/None]
    cur = None            # いま動かしている out の要素
    upd = {}
    mark = (dict(upd), True)   # 枝の始まりの切り替えと、確かか

    choice = [None]      # いまの選択肢の枝の文言
    local = {}           # このページの中で書いた変数

    def settle():
        """動かずに切り替えだけしたら (エレベーターの行き先ボタンなど)、その場に留まる行き先として残す。"""
        if cur is None and upd != mark[0]:
            out.append([('shift', 0, 0), mark[1], dict(upd), choice[0]])

    for c in (D(x) for x in D(page)['@list']):
        code, ind, q = c['@code'], c['@indent'], c['@parameters']
        if code == 411:
            for s_ in stack:
                if s_[0] == ind and s_[1] is not None:
                    s_[1] = not s_[1]
            continue
        if code == 102:
            before_choice = dict(upd)
        if code in (402, 403, 404):
            # 選択肢の枝はそれぞれ別の行き先。枝ごとに、選ぶ前の切り替えから始める
            settle()
            cur = None
            choice[0] = st(q[1]) if code == 402 else None
            upd = dict(before_choice) if 'before_choice' in locals() else dict(upd)
            mark = (dict(upd), None not in [s_[1] for s_ in stack if s_[0] < ind])
        stack = [s_ for s_ in stack if s_[0] < ind]
        vals = [s_[1] for s_ in stack]
        if False in vals:
            continue
        sure = None not in vals
        if code == 111:
            if q[0] == 1 and q[1] in local:
                v = local[q[1]]
                if isinstance(v, tuple):
                    lo, hi = v[1], v[2]
                    b = q[3] if q[2] == 0 else state.var(q[3])
                    # 乱数: 比べる値がとりうる幅に入っていれば、その枝もありうる (起きうる行き先として辿る)
                    possible = [any(op(a, b) for a in range(lo, hi + 1)) for op in
                                (lambda a, b: a == b, lambda a, b: a >= b, lambda a, b: a <= b,
                                 lambda a, b: a > b, lambda a, b: a < b, lambda a, b: a != b)][q[4]]
                    stack.append([ind, True if possible else False])
                else:
                    b = q[3] if q[2] == 0 else state.var(q[3])
                    stack.append([ind, [v == b, v >= b, v <= b, v > b, v < b, v != b][q[4]]])
            else:
                stack.append([ind, cond_111(state, mid, eid, q, facing, surf)])
        elif code == 115 and sure:
            break
        elif code == 121:
            for i in range(q[0], q[1] + 1):
                if ('S', i) in TOGGLES:
                    upd[('S', i)] = q[2] == 0
        elif code == 122 and q[2] == 0 and q[3] in (0, 1, 2):
            # 同じページのあとの分岐は、ここで書いた値を見る (乱数なら、どの値もありうる)
            for i in range(q[0], q[1] + 1):
                if q[3] == 0:
                    local[i] = q[4]
                elif q[3] == 1:
                    local[i] = state.var(q[4])
                else:
                    local[i] = ('rand', q[4], q[5])
                if q[3] == 0 and ('V', i) in TOGGLES:
                    upd[('V', i)] = q[4]
        elif code == 201 and q[0] == 0:
            cur = [('warp', q[1], q[2], q[3]), sure, upd, choice[0]]
            out.append(cur)
        elif code == 209 and q[0] == -1:
            dd = player_route(q[1], facing)
            if dd is None or dd == (0, 0):
                continue
            if cur is None:
                cur = [('shift', 0, 0), sure, upd, choice[0]]
                out.append(cur)
            cur[0] = cur[0][:-2] + (cur[0][-2] + dd[0], cur[0][-1] + dd[1])
            cur[1] = cur[1] and sure
    settle()
    res = []
    for p_, sure, u, label in out:
        item = (p_, sure, frozenset(u.items()), label)
        if item not in res:
            res.append(item)
    return res


# ---------------------------------------------------------------- 地図

class Map:
    def __init__(self, mid, state, approx=False):
        m = load_map(mid)
        self.id = mid
        self.state = state
        self.xs, self.ys, self.zs, self.cells = table(m['@data'])
        ts = TILESETS[m['@tileset_id']].data
        self.pas = table(ts['@passages'])[3]
        self.pri = table(ts['@priorities'])[3]
        self.tag = table(ts['@terrain_tags'])[3]
        self.ev_at = collections.defaultdict(list)    # (x, y) -> [(tile_id, character_name, through)]
        self.triggers = collections.defaultdict(list)  # (x, y) -> [(over, page, event_id)]
        self.refs = set()                              # この地図の条件に出る TOGGLES
        self.autoruns = []                             # [(page, event_id)] 自動実行・並列処理
        self.arrivals = []                             # [(page, event_id)] 入ったとたんに動く自動実行
        self._fx = {}
        for e in (D(x) for x in (m['@events'] or {}).values()):
            for p in e['@pages']:
                c = D(D(p)['@condition'])
                for k in ('1', '2'):
                    if c.get(f'@switch{k}_valid'):
                        self.refs.add(('S', c[f'@switch{k}_id']))
                if c.get('@variable_valid'):
                    self.refs.add(('V', c['@variable_id']))
                for cm in (D(x) for x in D(p)['@list']):
                    if cm['@code'] == 111 and cm['@parameters'][0] in (0, 1):
                        self.refs.add(('S' if cm['@parameters'][0] == 0 else 'V', cm['@parameters'][1]))
            pg = None
            for p in reversed(e['@pages']):
                if page_ok(state, mid, e['@id'], p):
                    pg = D(p)
                    break
            if approx:
                # 道の途中で切り替わる値で、別のページになりうるもの。どれも起こせるとして探し、
                # 見つかった道はあとで verify() が正しい値で確かめる
                # 会話のあるページは物語の場面なので、切り替えのあとのページとしては使わない
                alts = [p for p in self._alt_pages(e, pg, state) if not _talks(p)]
                for p in alts:
                    if p['@trigger'] in (0, 1, 2) and not removable(p):
                        self.triggers[(e['@x'], e['@y'])].append((self._over(e, p), p, e['@id']))
                    elif p['@trigger'] == 3:
                        self.arrivals.append((p, e['@id']))
                if pg is not None and any(self._open(p) for p in alts):
                    # どこかのページで道をあけるなら、ふさがないものとする
                    if pg['@trigger'] in (0, 1, 2) and not removable(pg):
                        self.triggers[(e['@x'], e['@y'])].append((self._over(e, pg), pg, e['@id']))
                    continue
            if pg is None or removable(pg, state):
                continue
            if pg['@trigger'] in (3, 4):
                self.autoruns.append((pg, e['@id']))
            if pg['@trigger'] == 3 and not _talks(pg):
                self.arrivals.append((pg, e['@id']))
            g = D(pg['@graphic'])
            cn = g.get('@character_name') or ''
            th = pg.get('@through', False)
            self.ev_at[(e['@x'], e['@y'])].append((g.get('@tile_id', 0), cn, th))
            if pg['@trigger'] in (0, 1, 2):
                self.triggers[(e['@x'], e['@y'])].append((self._over(e, pg), pg, e['@id']))
        self.refs &= set(TOGGLES)

    @staticmethod
    def _open(p):
        """そのページでは道をふさがない (絵がない・すり抜ける・消せる)。"""
        g = D(p['@graphic'])
        return p.get('@through', False) or removable(p) or not (g.get('@character_name') or g.get('@tile_id'))

    @staticmethod
    def _over(e, p):
        """over_trigger? (Game_Event) の前半: 絵がないか、すり抜ける。HiddenItem は除く。
        後半の「そのマスが通れる」は、全部のイベントを並べてから trigger_over で見る。"""
        g = D(p['@graphic'])
        cn = g.get('@character_name') or ''
        return ((not cn and not g.get('@tile_id')) or p.get('@through', False)) and st(e['@name']) != 'HiddenItem'

    def _alt_pages(self, e, pg, state):
        """道の途中で切り替わる値 (TOGGLES) しだいで、表に出うるほかのページ。

        ページは番号の大きいほうから見て、条件を満たす最初のものが表に出る。そこで大きい
        ほうから順に、切り替わる値でなら条件を満たせるページを拾い、切り替わる値に頼らずに
        条件を満たすページに行き当たったら、それより下は出ないので止める。"""
        out = []
        for p in reversed(e['@pages']):
            p = D(p)
            c = D(p['@condition'])
            ok, sure = True, True
            for k in ('1', '2'):
                if c.get(f'@switch{k}_valid'):
                    i = c[f'@switch{k}_id']
                    if ('S', i) in TOGGLES:
                        sure = False
                        if not state.switch(i) and True not in TOGGLES[('S', i)]:
                            ok = False
                    elif not state.switch(i):
                        ok = False
            if c.get('@variable_valid'):
                i, need = c['@variable_id'], c['@variable_value']
                if ('V', i) in TOGGLES:
                    sure = False
                    if state.var(i) < need and not any(v >= need for v in TOGGLES[('V', i)]):
                        ok = False
                elif state.var(i) < need:
                    ok = False
            if c.get('@self_switch_valid') and not state.selfswitch(self.id, e['@id'], st(c['@self_switch_ch'])):
                ok = False
            if not ok:
                continue
            if p is not pg:
                out.append(p)
            if sure:
                break
        return out

    def entry_updates(self):
        """地図に入ったときに動く自動実行・並列処理が、条件なしに書き換える TOGGLES。"""
        if not hasattr(self, '_entry'):
            upd = {}
            for pg, eid in self.autoruns:
                stack = []
                for c in (D(x) for x in pg['@list']):
                    code, ind, q = c['@code'], c['@indent'], c['@parameters']
                    if code == 411:
                        for s_ in stack:
                            if s_[0] == ind and s_[1] is not None:
                                s_[1] = not s_[1]
                        continue
                    stack = [s_ for s_ in stack if s_[0] < ind]
                    if any(s_[1] is not True for s_ in stack):
                        if code == 111:
                            stack.append([ind, None])
                        continue
                    if code == 111:
                        stack.append([ind, cond_111(self.state, self.id, eid, q)])
                    elif code == 121:
                        for i in range(q[0], q[1] + 1):
                            if ('S', i) in TOGGLES:
                                upd[('S', i)] = q[2] == 0
                    elif code == 122 and q[2] == 0 and q[3] == 0:
                        for i in range(q[0], q[1] + 1):
                            if ('V', i) in TOGGLES:
                                upd[('V', i)] = q[4]
            self._entry = upd
        return self._entry

    def arrival(self):
        """入ったとたんに自動実行が主人公を動かす行き先。[(行き先, 確か, 切り替え)]"""
        if not hasattr(self, '_arr'):
            res = []
            for pg, eid in self.arrivals:
                res.extend(run_page(self.state, self.id, eid, pg, None))
            self._arr = res
        return self._arr

    def effects(self, x, y, d, surf=False):
        """(x, y) のイベントに d の向きで触れたときの行き先。[(行き先, 確か, 切り替え)]"""
        key = (x, y, d, surf)
        if key not in self._fx:
            res = []
            for over, pg, eid in self.triggers.get((x, y), []):
                res.extend(run_page(self.state, self.id, eid, pg, d, surf))
            self._fx[key] = res
        return self._fx[key]

    def warps(self):
        """場所移動のあるマスと行き先 (向きを問わず)。{(x, y): [(地図, x, y, 確か)]}"""
        out = {}
        for xy in self.triggers:
            for d in DIRS:
                for (kind, *rest), sure, _u, _l in self.effects(*xy, d):
                    if kind == 'warp':
                        v = (rest[0], rest[1], rest[2], sure)
                        if v not in out.setdefault(xy, []):
                            out[xy].append(v)
        return out

    def trigger_over(self, x, y):
        """上に乗って起こすイベントか (Game_Event#over_trigger?)。通れないマスにあるものは、
        ぶつかって起こす (check_event_trigger_touch)。"""
        return any(t[0] for t in self.triggers.get((x, y), [])) and self.passable(x, y, 0)

    def valid(self, x, y):
        return 0 <= x < self.xs and 0 <= y < self.ys

    def tile(self, x, y, z):
        return self.cells[x + y * self.xs + z * self.xs * self.ys]

    def terrain(self, x, y):
        for z in (2, 1, 0):
            t = self.tag[self.tile(x, y, z)]
            if t > 0:
                return t
        return 0

    def passable(self, x, y, d, surf=False):
        """Game_Map#passable? → playerPassable? と同じ順で見る。"""
        bit = (1 << (d // 2 - 1)) & 0x0f if d else 0
        for (tid, _cn, th) in self.ev_at.get((x, y), ()):
            if not th and tid > 0:
                if self.pas[tid] & bit or self.pas[tid] & 0x0f == 0x0f:
                    return False
                if self.pri[tid] == 0:
                    return True
        for z in (2, 1, 0):
            tid = self.tile(x, y, z)
            if surf and self.tag[tid] in PASS_WATER:
                return True
            if self.pas[tid] & bit or self.pas[tid] & 0x0f == 0x0f:
                return False
            if self.pri[tid] == 0:
                return True
        return True

    def occupied(self, x, y):
        return any(not th and cn for (_t, cn, th) in self.ev_at.get((x, y), ()))


# ---------------------------------------------------------------- 世界

EMPTY = frozenset()


class World:
    def __init__(self, state, exact=False):
        """exact=False は、切り替わる値を持ち歩かずに、どの値のページも起こせるとして探す
        (速い)。exact=True は値を持ち歩く (道を確かめるのに使う)。"""
        self.state = state
        self.exact = exact
        self.maps = {}
        self.conns = collections.defaultdict(list)   # mid -> [(other, dx, dy)]  other座標 = 自分座標 + (dx, dy)
        for m1, x1, y1, m2, x2, y2 in rmarshal.load(f'{GAME}/Data/connections.dat'):
            self.conns[m1].append((m2, x2 - x1, y2 - y1))
            self.conns[m2].append((m1, x1 - x2, y1 - y2))

    def get(self, mid, tog=EMPTY):
        """tog は道の途中で切り替わった値。この地図の条件に出るものだけで地図を作り分ける。"""
        base = self.maps.get((mid, EMPTY))
        if base is None:
            if (mid, EMPTY) in self.maps or load_map(mid) is None:
                self.maps[(mid, EMPTY)] = None
                return None
            base = self.maps[(mid, EMPTY)] = Map(mid, self.state, approx=not self.exact)
        if not self.exact:
            return base
        sub = frozenset(kv for kv in tog if kv[0] in base.refs)
        if not sub:
            return base
        if (mid, sub) not in self.maps:
            self.maps[(mid, sub)] = Map(mid, Overlay(self.state, sub))
        return self.maps[(mid, sub)]

    def arrive(self, mid, x, y, tog, depth=0):
        """場所移動で着いたところ。着いた地図の自動実行が主人公を動かすなら、その先まで。"""
        M = self.get(mid, tog)
        outs = M.arrival() if M is not None else []
        if not outs or depth > 3:
            return [((mid, x, y, tog), True)]
        res = []
        for (kind, *rest), sure, upd, _label in outs:
            t2 = tog
            if upd and self.exact:
                dct = dict(tog)
                dct.update(upd)
                t2 = frozenset(dct.items())
            if kind == 'warp':
                nxt = (rest[0], rest[1], rest[2])
            else:
                nxt = (mid, x + rest[0], y + rest[1])
            N = self.get(nxt[0], t2)
            if N is None or not N.valid(nxt[1], nxt[2]):
                continue
            if nxt[0] == mid and kind != 'warp':
                res.append(((nxt[0], nxt[1], nxt[2], t2), sure))
            else:
                for r, s2 in self.arrive(nxt[0], nxt[1], nxt[2], t2, depth + 1):
                    res.append((r, sure and s2))
        return res or [((mid, x, y, tog), True)]

    def locate(self, mid, x, y, tog=EMPTY):
        """地図の外に出た座標を、つながっている地図の座標に直す。"""
        L = self.get(mid, tog)
        if L.valid(x, y):
            return L, mid, x, y
        for other, dx, dy in self.conns.get(mid, []):
            O = self.get(other, tog)
            if O and O.valid(x + dx, y + dy):
                return O, other, x + dx, y + dy
        return None, None, None, None

    def moves(self, mid, x, y, surf=False, tog=EMPTY):
        """(行き先 (地図, x, y, 波乗り中か, 切り替え), 種類) を返す。

        値を持ち歩くとき (exact) は、行き先の地図の条件に出る値だけを残す。ほかの地図で
        切り替えた値は、その地図に入り直すときのイベントが書き直すことが多く、持ち歩くと
        状態の数だけが増えるため。"""
        for n, k in self._moves(mid, x, y, surf, tog):
            if self.exact and n[4]:
                near = self.near_refs(n[0])
                keep = frozenset(kv for kv in n[4] if kv[0] in near)
                if keep != n[4]:
                    n = (n[0], n[1], n[2], n[3], keep)
            yield n, k

    def near_refs(self, mid, hops=2):
        """その地図と、扉やつながりで2つ先までの地図の条件に出る値。持ち歩く値はこの中だけ。"""
        if not hasattr(self, '_near'):
            self._near = {}
        if mid not in self._near:
            seen, frontier = {mid}, {mid}
            for _ in range(hops):
                nxt = set()
                for m in frontier:
                    L = self.get(m)
                    if L is None:
                        continue
                    for ds in L.warps().values():
                        nxt.update(d[0] for d in ds)
                    nxt.update(o for o, _dx, _dy in self.conns.get(m, []))
                nxt -= seen
                seen |= nxt
                frontier = nxt
            refs = set()
            for m in seen:
                L = self.get(m)
                if L is not None:
                    refs |= L.refs
            self._near[mid] = refs
        return self._near[mid]

    def _moves(self, mid, x, y, surf=False, tog=EMPTY):
        L = self.get(mid, tog)
        st_ = self.state
        for d, (dx, dy) in DIRS.items():
            T, tm, tx, ty = self.locate(mid, x + dx, y + dy, tog)
            if T is None:
                continue
            step_upd = None     # そのマスを踏むと起きる、動かない切り替え (歩きに載せる)
            if (tx, ty) in T.triggers:
                over = T.trigger_over(tx, ty)
                enter_ok = (L.passable(x, y, d, surf) and T.passable(tx, ty, 10 - d, surf)
                            and not T.occupied(tx, ty))
                for (kind, *rest), sure, upd, label in T.effects(tx, ty, d, surf):
                    tog2 = tog
                    if upd and self.exact:
                        dct = dict(tog)
                        dct.update(upd)
                        tog2 = frozenset(dct.items())
                    if kind == 'warp':
                        D2 = self.get(rest[0], tog2)
                        if self.exact and D2 is not None and D2.entry_updates():
                            dct = dict(tog2)
                            dct.update(D2.entry_updates())
                            tog2 = frozenset(dct.items())
                            D2 = self.get(rest[0], tog2)
                        if D2 is not None and D2.valid(rest[1], rest[2]):
                            for (m3, x3, y3, t3), sure3 in self.arrive(rest[0], rest[1], rest[2], tog2):
                                D3 = self.get(m3, t3)
                                # 場所移動のあとも波乗りを続けるのは、行き先が水のときだけ
                                s2 = surf and D3.terrain(x3, y3) in SURFABLE
                                ok = sure and sure3
                                yield (m3, x3, y3, s2, t3), 'door' if ok else 'door?'
                        continue
                    if rest == [0, 0]:
                        if over and enter_ok and sure and not label:
                            # 踏むと起きる切り替え。下の歩きの一歩に載せる
                            step_upd = tog2
                            continue
                        # 動かずに切り替えるだけ (エレベーターのボタンなど)。値を持ち歩くときだけ意味がある
                        if self.exact and tog2 != tog:
                            # 選択肢で選んだものなら、その文言を種類に添える (案内の文に使う)
                            yield (mid, x, y, surf, tog2), 'switch' + (':' + label if label else '')
                        continue
                    # 移動ルートで主人公が動く (階段・飛び移りなど)。上に乗って起こすイベントは
                    # 乗ったマスから、ぶつかって起こすイベントはいまのマスから動く
                    if over and not enter_ok:
                        continue
                    om, ox, oy = (tm, tx, ty) if over else (mid, x, y)
                    U, um, ux, uy = self.locate(om, ox + rest[0], oy + rest[1], tog2)
                    if U is not None:
                        s2 = surf and U.terrain(ux, uy) in SURFABLE
                        yield (um, ux, uy, s2, tog2), 'script' if sure else 'door?'
            ftag = T.terrain(tx, ty)
            if T.occupied(tx, ty):
                continue
            if not surf:
                if L.passable(x, y, d) and T.passable(tx, ty, 10 - d):
                    if ftag == ICE or ftag in CONVEYOR:
                        end = self.slide(T, tm, tx, ty, d, tog)
                        if end is not None:
                            yield (end[0], end[1], end[2], False, tog), 'slide'
                        continue
                    if ftag == LEDGE:
                        U, um, ux, uy = self.locate(tm, tx + dx, ty + dy, tog)
                        if U is not None and U.passable(ux, uy, 0) and not U.occupied(ux, uy):
                            yield (um, ux, uy, False, tog), 'jump'
                        continue
                    yield (tm, tx, ty, False, step_upd if self.exact and step_upd else tog), 'walk' if tm == mid else 'edge'
                elif (st_.can_surf and ftag in SURFABLE
                      and L.passable(x, y, d, True) and T.passable(tx, ty, 10 - d, True)):
                    # 水に向かって調べると波乗り (pbSurf → pbStartSurfing で1マス跳ぶ)
                    yield (tm, tx, ty, True, tog), 'surf'
                continue
            # 波乗り中
            if d == 8 and ftag == WATERFALL and st_.can_waterfall:
                # pbAscendWaterfall: 滝のマスが続くかぎり上へ
                ny = ty
                while T.valid(tx, ny - 1) and T.terrain(tx, ny) in (WATERFALL, CREST):
                    ny -= 1
                yield (tm, tx, ny, True, tog), 'waterfall_up'
                continue
            if not (L.passable(x, y, d, True) and T.passable(tx, ty, 10 - d, True)):
                continue
            if L.terrain(x, y) in SURFABLE and ftag not in SURFABLE:
                yield (tm, tx, ty, False, tog), 'land'          # pbEndSurf
                continue
            if ftag == CREST and d == 2:
                # 滝の上から下向きに入ると pbDescendWaterfall で下まで降りる
                ny = ty
                while T.valid(tx, ny + 1) and T.terrain(tx, ny + 1) in (WATERFALL, CREST):
                    ny += 1
                if T.valid(tx, ny + 1):
                    ny += 1
                yield (tm, tx, ny, True, tog), 'waterfall_down'
                continue
            yield (tm, tx, ty, True, tog), 'swim' if tm == mid else 'edge'


def _slide(world, T, tm, x, y, d, tog):
    """氷の上は、通れなくなるか氷でなくなるまで同じ向きに滑る (pbSlideOnIce)。
    ベルトコンベアは、タグの向きへ運ばれる (pbConveyorMove)。"""
    seen = set()
    while True:
        if (tm, x, y) in seen:
            return None                   # 輪になって止まらない
        seen.add((tm, x, y))
        tag = T.terrain(x, y)
        if tag in CONVEYOR:
            d = CONVEYOR[tag]
        elif tag != ICE:
            return (tm, x, y)
        dx, dy = DIRS[d]
        U, um, ux, uy = world.locate(tm, x + dx, y + dy, tog)
        if U is None or not T.passable(x, y, d) or not U.passable(ux, uy, 10 - d) or U.occupied(ux, uy):
            return (tm, x, y)
        T, tm, x, y = U, um, ux, uy


World.slide = lambda self, T, tm, x, y, d, tog: _slide(self, T, tm, x, y, d, tog)


def node(mid, x, y, surf=False, tog=EMPTY):
    return (mid, x, y, surf, tog)


def explore(world, start, allow_uncertain=False):
    """start から行けるところを全部。{状態: (前の状態, 種類)}"""
    prev = {start: None}
    q = collections.deque([start])
    while q:
        cur = q.popleft()
        for n, k in world.moves(*cur):
            if k == 'door?' and not allow_uncertain:
                continue
            if n not in prev:
                prev[n] = (cur, k)
                q.append(n)
    return prev


def verify(state, path, kinds, repair=True, radius=20000, where=None):
    """見つけた道を、切り替わる値を持ち歩いてもう一度たどる。

    通れなくなる一歩があれば、その手前から近くを正しい値で探し直して、つなぎ直す
    (エレベーターの行き先ボタンを押しに寄る、など)。つなげたら (道, 種類) を、
    つなげなければ None を返す (where にリストを渡すと、あきらめた一歩の番号を入れる)。"""
    W = World(state, exact=True)
    cur = node(*path[0])
    out_p, out_k = [tuple(path[0])], []
    i = 0
    while i < len(kinds):
        want = tuple(path[i + 1])
        nxt = None
        for n, k2 in W.moves(*cur):
            if n[:4] == want and k2 != 'door?':
                nxt, kind = n, k2
                break
        if nxt is None:
            if not repair:
                if where is not None:
                    where.append(i)
                return None
            # 近くを幅優先で探して、次の地点にたどり着く道を差し込む
            prev = {cur: None}
            q = collections.deque([cur])
            hit = None
            while q and len(prev) < radius:
                c = q.popleft()
                if c[:4] == want:
                    hit = c
                    break
                for n, k2 in W.moves(*c):
                    if k2 != 'door?' and n not in prev:
                        prev[n] = (c, k2)
                        q.append(n)
            if hit is None:
                if where is not None:
                    where.append(i)
                return None
            seg = []
            c = hit
            while prev[c] is not None:
                seg.append((c, prev[c][1]))
                c = prev[c][0]
            for n, k2 in reversed(seg):
                out_p.append(n[:4])
                out_k.append(k2)
            cur = hit
            i += 1
            continue
        out_p.append(nxt[:4])
        out_k.append(kind)
        cur = nxt
        i += 1
    return out_p, out_k


STEP, TURN = 1000, 1   # 歩数が最短のもののうち、曲がる回数が少ない道


def search(world, start, goal_fn, allow_uncertain=False, limit=5_000_000):
    """start は node()。道は [(地図, x, y, 波乗り中か)] と、各一歩の種類。"""
    s0 = (start, (0, 0))
    best = {s0: 0}
    prev = {s0: None}
    tie = itertools.count()
    q = [(0, 0, s0)]
    while q:
        cost, _, cur = heapq.heappop(q)
        if cost > best[cur]:
            continue
        nd, cdir = cur
        if goal_fn(nd):
            path = []
            c = cur
            while c is not None:
                path.append(c)
                c = prev[c][0] if prev[c] else None
            path.reverse()
            return [p[0][:4] for p in path], [prev[p][1] for p in path[1:]]
        for n, k in world.moves(*nd):
            if k == 'door?' and not allow_uncertain:
                continue
            if k in ('door', 'door?'):
                d = (0, 0)
            elif n[0] == nd[0]:
                d = (max(-1, min(1, n[1] - nd[1])), max(-1, min(1, n[2] - nd[2])))
            else:
                d = cdir
            c2 = cost + STEP + (TURN if cdir != (0, 0) and d != (0, 0) and d != cdir else 0)
            ns = (n, d)
            if c2 < best.get(ns, 1 << 60):
                best[ns] = c2
                prev[ns] = (cur, k)
                heapq.heappush(q, (c2, next(tie), ns))
                if len(best) > limit:
                    return None, None
    return None, None
