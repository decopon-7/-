#!/usr/bin/env python3
"""canva-assembly-guide.md から、ページごとの秒数と切替を読み取って timeline.json を作る。

使い方:  python3 make_timeline.py            (../canva-assembly-guide.md を読む)
"""
import json, re, sys, pathlib

GUIDE = pathlib.Path(__file__).resolve().parent.parent / "canva-assembly-guide.md"

# ガイドの「切替」を ffmpeg の xfade の名前に置き換える対応表。
# マッチ&ムーブは「素材が動く」機能なので、画像だけでは再現できない。
# ズーム／パン／ジャンプの見た目に近い xfade で代用する（下の MATCH_MOVE_LOOK で個別指定）。
KIND_TO_XFADE = {
    "ディゾルブ": "dissolve",
    "サークルワイプ": "circleopen",
    "カラーワイプ": "wipeleft",     # xfade には色付きワイプがないので、普通のワイプで代用
    "マッチ&ムーブ": "fade",        # 既定。個別に上書きする
}
# マッチ&ムーブの代用（ページ番号 -> xfade 名）。入りのページ番号で指定する。
MATCH_MOVE_LOOK = {
    8: "zoomin",       # 手紙がズームイン
    10: "zoomin",      # 顔にズームイン
    21: "zoomin",      # トリケラにズーム
    30: "slideleft",   # 歩いて右へ
    34: "fade",
    35: "slideleft",   # 右を見る（ゆっくりパン）
    36: "slideright",  # 全体に戻る
    44: "zoomin",      # ステゴの岩にズーム
    48: "zoomin",      # しっぽにズーム
    49: "fade",
    63: "slidedown",   # 見上げる
    68: "zoomin",      # プテラにズーム
    69: "fade",
}

def main():
    text = GUIDE.read_text(encoding="utf-8").split("\n")
    pages = {}        # n -> dict
    cur = None
    for line in text:
        m = re.match(r"^\*\*P(\d+)(?:〜P(\d+))?｜([\d.]+)秒(?:×(\d+)ページ)?｜?(.*?)\*\*", line)
        if m:
            a = int(m.group(1)); b = int(m.group(2)) if m.group(2) else a
            dur = float(m.group(3))
            title = m.group(5)
            cur = []
            for n in range(a, b + 1):
                pages[n] = {"page": n, "dur": dur, "title": title, "transition": None}
                cur.append(n)
            continue
        if line.startswith(("---", "## ", "### ")):
            cur = None
        if not cur:
            continue
        t = re.match(r"^- 切替（P\d+→P(\d+)）：(.*)$", line)
        if t:
            n = int(t.group(1)); rest = t.group(2).strip()
            if rest.startswith("なし"):
                continue
            sec_m = re.search(r"([\d.]+)秒", rest)
            sec = float(sec_m.group(1)) if sec_m else 0.8
            for k, v in KIND_TO_XFADE.items():
                if rest.startswith(k):
                    x = MATCH_MOVE_LOOK.get(n, v) if k == "マッチ&ムーブ" else v
                    pages[n]["transition"] = {"kind": k, "xfade": x, "dur": sec}
                    break
    out = [pages[n] for n in sorted(pages)]
    missing = [n for n in range(1, 85) if n not in pages]
    if missing:
        print("ガイドに秒数がないページ:", missing, file=sys.stderr)
    dst = pathlib.Path(__file__).resolve().parent / "timeline.json"
    dst.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    total = sum(p["dur"] for p in out)
    print(f"{len(out)}ページ / 合計 {total:.1f}秒 → {dst}")

if __name__ == "__main__":
    main()
