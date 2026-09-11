# 章ごとの進み具合を組み立てる道具

`_ja/navi/README.md` の「ほかの章」の手順を実行するもの。14章のセーブ (`_ja/navi/states/ch14.json`) を軸にする。

    python3 relevance.py   # 道に効くスイッチ・変数・セルフスイッチを選ぶ → choke2.pkl
    python3 derive.py      # イベントの見積もりで章ごとの値を決める → derive.pkl
    python3 sens.py 5      # 5章の仮の状態で、行ける範囲を変える値を拾う (手で決める候補)
    python3 validate.py 5  # 5章の本文の見出しに出る場所へ行けるか

手で決めた値は `decisions.json`、その根拠は `_ja/navi/decisions.md`。
章の状態ファイルは `states.make_state(n)` で作り、`State.dump()` で `_ja/navi/states/ch<n>.json` に書く。
`*.pkl` は作り直せるので追跡しない。
