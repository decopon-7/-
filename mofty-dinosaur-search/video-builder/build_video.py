#!/usr/bin/env python3
"""Canva から書き出したページ画像 + timeline.json から、切替・音つきの動画(mp4)を作る。

必要なもの: Python 3.8+ と ffmpeg（4.4 以上）。  ffmpeg が無ければ:  pip install imageio-ffmpeg

使い方（例）:
  python3 build_video.py --images ./pages --out mofty.mp4
  python3 build_video.py --images ./pages --out mofty.mp4 --audio audio.json
  python3 build_video.py --images ./pages --out test.mp4 --pages 1-14 --res 960x540 --fps 15   # 試し書き出し

--images には、Canva で「ダウンロード → PNG → すべてのページ」で書き出した画像のフォルダを指定する。
ファイル名の末尾の数字をページ番号として使う（例: "モフティ - 12.png" → P12）。
"""
import argparse, json, os, re, shutil, subprocess, sys, pathlib

HERE = pathlib.Path(__file__).resolve().parent


def find_ffmpeg():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        sys.exit("ffmpeg が見つかりません。ffmpeg を入れるか、`pip install imageio-ffmpeg` を実行してください。")


def page_images(folder):
    found = {}
    for f in sorted(pathlib.Path(folder).iterdir()):
        if f.suffix.lower() not in (".png", ".jpg", ".jpeg"):
            continue
        m = re.findall(r"(\d+)", f.stem)
        if m:
            found[int(m[-1])] = f
    return found


def parse_range(s, lo, hi):
    if not s:
        return lo, hi
    a, _, b = s.partition("-")
    return int(a), int(b or a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", required=True, help="ページ画像のフォルダ")
    ap.add_argument("--timeline", default=str(HERE / "timeline.json"))
    ap.add_argument("--audio", help="audio.json（任意）")
    ap.add_argument("--out", default="mofty.mp4")
    ap.add_argument("--res", default="1920x1080")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--pages", help="例: 1-14（試し書き出し用）")
    ap.add_argument("--time-scale", type=float, default=1.0, help="秒数を何倍にするか（試し用に0.2など）")
    ap.add_argument("--dry-run", action="store_true", help="ffmpegを実行せず、コマンドだけ表示")
    a = ap.parse_args()

    ff = find_ffmpeg()
    W, H = (int(x) for x in a.res.lower().split("x"))
    tl = {p["page"]: p for p in json.load(open(a.timeline, encoding="utf-8"))}
    imgs = page_images(a.images)
    lo, hi = parse_range(a.pages, min(tl), max(tl))
    nums = [n for n in range(lo, hi + 1) if n in tl]
    missing = [n for n in nums if n not in imgs]
    if missing:
        sys.exit(f"画像が見つかりません: P{missing}（ファイル名の末尾にページ番号が必要です）")

    S = a.time_scale
    d = {n: tl[n]["dur"] * S for n in nums}
    # 切替: ページ n の「入り」。先頭ページと、前ページと重ねられない短い切替は切る
    t = {}
    for i, n in enumerate(nums):
        tr = tl[n].get("transition")
        if not tr or i == 0:
            t[n] = 0.0
            continue
        prev = nums[i - 1]
        t[n] = round(min(tr["dur"] * S, d[prev] * 0.8, d[n] * 0.8), 3)
    xf = {n: (tl[n]["transition"]["xfade"] if t[n] > 0 else None) for n in nums}

    # 各クリップの長さ = 自分の秒数 + 次ページへの切替の重なり分
    L = {}
    for i, n in enumerate(nums):
        nxt = t[nums[i + 1]] if i + 1 < len(nums) else 0.0
        L[n] = d[n] + nxt

    cmd = [ff, "-y", "-hide_banner", "-loglevel", "warning", "-stats"]
    for n in nums:
        cmd += ["-framerate", str(a.fps), "-loop", "1", "-t", f"{L[n]:.3f}", "-i", str(imgs[n])]
    fc = []
    for k, n in enumerate(nums):
        fc.append(f"[{k}:v]scale={W}:{H}:force_original_aspect_ratio=decrease,"
                  f"pad={W}:{H}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps={a.fps},format=yuv420p[v{k}]")
    cur = "v0"
    acc = 0.0           # ここまでの「秒数の合計」= 次の切替の開始位置
    for k in range(1, len(nums)):
        n = nums[k]
        acc += d[nums[k - 1]]
        out = f"m{k}"
        if xf[n]:
            fc.append(f"[{cur}][v{k}]xfade=transition={xf[n]}:duration={t[n]:.3f}:offset={acc:.3f}[{out}]")
        else:
            fc.append(f"[{cur}][v{k}]concat=n=2:v=1:a=0,settb=1/{a.fps},fps={a.fps}[{out}]")
        cur = out
    total = sum(d.values())

    # 音
    n_in = len(nums)
    audio_labels = []
    if a.audio:
        starts, ends, x = {}, {}, 0.0
        for n in nums:
            starts[n] = x; x += d[n]; ends[n] = x
        for j, e in enumerate(json.load(open(a.audio, encoding="utf-8"))):
            f = pathlib.Path(e["file"])
            if not f.is_absolute():
                f = pathlib.Path(a.audio).resolve().parent / f
            if not f.exists():
                print(f"音声ファイルが無いのでスキップ: {f}", file=sys.stderr)
                continue
            p0 = e.get("from_page", e.get("at_page"))
            if p0 not in starts:
                continue
            start = starts[p0] + e.get("offset", 0.0) * S
            end = ends[e["to_page"]] if e.get("to_page") in ends else None
            loop = ["-stream_loop", "-1"] if e.get("loop") else []
            cmd += loop + ["-i", str(f)]
            lab = f"a{j}"
            chain = f"[{n_in}:a]"
            filt = []
            if end is not None:
                dur = max(end - start, 0.1)
                filt.append(f"atrim=0:{dur:.3f}")
                fo = e.get("fade_out", 0)
                if fo:
                    filt.append(f"afade=t=out:st={max(dur - fo, 0):.3f}:d={fo}")
            filt.append(f"volume={e.get('volume', 1.0)}")
            filt.append(f"adelay={int(start * 1000)}|{int(start * 1000)}")
            fc.append(chain + ",".join(filt) + f"[{lab}]")
            audio_labels.append(f"[{lab}]")
            n_in += 1
    maps = ["-map", f"[{cur}]"]
    if audio_labels:
        fc.append("".join(audio_labels) + f"amix=inputs={len(audio_labels)}:normalize=0:duration=longest[aout]")
        maps += ["-map", "[aout]"]
    cmd += ["-filter_complex", ";".join(fc)] + maps
    cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p"]
    if audio_labels:
        cmd += ["-c:a", "aac", "-b:a", "192k"]
    cmd += ["-t", f"{total:.3f}", "-movflags", "+faststart", a.out]

    print(f"{len(nums)}ページ / 合計 {total:.1f}秒 / 切替 {sum(1 for n in nums if xf[n])}箇所 / 音 {len(audio_labels)}本")
    if a.dry_run:
        print(" ".join(f'"{c}"' if " " in c or ";" in c else c for c in cmd))
        return
    subprocess.run(cmd, check=True)
    print("できました:", a.out)


if __name__ == "__main__":
    main()
