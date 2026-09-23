#!/usr/bin/env python3
"""BGM「仕込み場のボサノバ」を合成して audio/bgm_bistro.wav に書き出す。

外部ライブラリ不要（標準の Python 3 だけで動く）。
曲を変えたいときは、下の CHORDS（コード進行）や MELODY（メロディ）を書き換えて
    python3 tools/make_bgm.py
を実行し、Godot で開き直せば反映される。

構成: 112 BPM・4/4 拍子・16小節でループ（約34秒）
  マリンバ風のメロディ / エレピのコード / ウッドベース風 / ブラシのシェイカー・リム・キック
"""
import array
import math
import os
import random
import wave

RATE = 22050
BPM = 112
BEAT = 60.0 / BPM
BARS = 16
LENGTH = int(BARS * 4 * BEAT * RATE)

random.seed(7)
buf = array.array("f", [0.0]) * LENGTH


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def add(start_beat, dur_sec, fn):
    """start_beat 拍目から dur_sec 秒の音を足す。曲の終わりをはみ出した分は先頭に回り込む（ループ用）。"""
    start = int(start_beat * BEAT * RATE)
    n = int(dur_sec * RATE)
    for i in range(n):
        buf[(start + i) % LENGTH] += fn(i / RATE)


def release(t, dur, rel=0.04):
    """音の終わりを短くフェードアウト"""
    return 1.0 if t < dur - rel else max(0.0, (dur - t) / rel)


# ---------------------------------------------------------------- 楽器

def marimba(note, dur_beats, vel=1.0):
    f = midi_hz(note)
    d = min(1.2, dur_beats * BEAT + 0.5)

    def fn(t):
        a = min(1.0, t / 0.003)
        v = math.sin(2 * math.pi * f * t) * math.exp(-t * 5.0)
        v += math.sin(2 * math.pi * f * 4.0 * t) * math.exp(-t * 22.0) * 0.3
        v += math.sin(2 * math.pi * f * 10.0 * t) * math.exp(-t * 60.0) * 0.08
        return v * a * release(t, d) * 0.22 * vel
    return d, fn


def epiano(note, dur_beats, vel=1.0):
    f = midi_hz(note)
    d = dur_beats * BEAT + 0.1

    def fn(t):
        a = min(1.0, t / 0.006)
        mod = math.sin(2 * math.pi * f * t) * 1.2 * math.exp(-t * 4.0)
        v = math.sin(2 * math.pi * f * t + mod) * math.exp(-t * 1.6)
        return v * a * release(t, d, 0.08) * 0.055 * vel
    return d, fn


def bass(note, dur_beats):
    f = midi_hz(note)
    d = dur_beats * BEAT

    def fn(t):
        a = min(1.0, t / 0.008)
        v = math.sin(2 * math.pi * f * t) + math.sin(2 * math.pi * f * 2 * t) * 0.25 * math.exp(-t * 6)
        return v * a * math.exp(-t * 1.8) * release(t, d, 0.05) * 0.3
    return d, fn


def kick():
    def fn(t):
        phase = 2 * math.pi * (48 * t + 70 * (1 - math.exp(-30 * t)) / 30)
        return math.sin(phase) * math.exp(-t * 16) * 0.3
    return 0.25, fn


def rim():
    def fn(t):
        return (math.sin(2 * math.pi * 1650 * t) * 0.6 + random.uniform(-1, 1) * 0.4) * math.exp(-t * 90) * 0.12
    return 0.08, fn


def shaker(accent):
    state = [0.0]

    def fn(t):
        n = random.uniform(-1, 1)
        state[0] += (n - state[0]) * 0.5
        hp = n - state[0]
        env = min(1.0, t / 0.01) * math.exp(-t * 35)
        return hp * env * (0.07 if accent else 0.04)
    return 0.12, fn


def play(beat, inst):
    d, fn = inst
    add(beat, d, fn)


# ---------------------------------------------------------------- 楽譜

# 1小節ごとのコード: (ベースの音, [コードの音...])。2つあるときは前半・後半
C, D, E, F, G, A = 36, 38, 40, 41, 43, 33
CMAJ7 = (C, [55, 59, 64, 67])
AM7 = (A, [55, 60, 64, 67])
DM7 = (D, [57, 60, 65, 69])
G7 = (G, [55, 59, 62, 65])
C6 = (C, [55, 60, 64, 69])
FMAJ7 = (F, [53, 57, 60, 64])
EM7 = (E, [55, 59, 62, 64])
E7 = (E, [56, 59, 62, 64])
D7 = (D, [54, 57, 60, 62])
CHORDS = [
    [CMAJ7], [AM7], [DM7], [G7], [CMAJ7], [AM7], [DM7, G7], [C6],
    [FMAJ7], [EM7], [DM7], [G7], [FMAJ7], [E7], [AM7, D7], [DM7, G7],
]

# メロディ: 小節ごとに (拍, MIDIノート, 長さ[拍])
MELODY = [
    [(0, 76, .5), (.5, 79, .5), (1, 76, .5), (1.5, 74, .5), (2, 72, 1), (3.5, 67, .5)],
    [(0, 69, .5), (.5, 72, .5), (1, 76, 1), (2, 74, .5), (2.5, 72, .5), (3, 69, 1)],
    [(0, 77, .5), (.5, 76, .5), (1, 74, .5), (1.5, 72, .5), (2, 69, 1), (3, 65, .5), (3.5, 69, .5)],
    [(0, 71, 1), (1, 74, .5), (1.5, 77, .5), (2, 76, .5), (2.5, 74, .5), (3, 71, 1)],
    [(0, 76, .5), (.5, 79, .5), (1, 84, 1), (2, 83, .5), (2.5, 79, .5), (3, 76, 1)],
    [(0, 81, 1), (1, 79, .5), (1.5, 76, .5), (2, 72, 1), (3, 76, .5), (3.5, 74, .5)],
    [(0, 74, .5), (.5, 77, .5), (1, 81, 1), (2, 79, .5), (2.5, 77, .5), (3, 74, .5), (3.5, 71, .5)],
    [(0, 72, 1.5), (2, 67, .5), (2.5, 69, .5), (3, 72, .5), (3.5, 76, .5)],
    [(0, 81, 1), (1, 79, .5), (1.5, 77, .5), (2, 76, 1), (3, 72, 1)],
    [(0, 79, 1), (1, 76, .5), (1.5, 74, .5), (2, 71, 1), (3, 67, .5), (3.5, 71, .5)],
    [(0, 74, .5), (.5, 76, .5), (1, 77, .5), (1.5, 81, .5), (2, 84, 1), (3, 81, 1)],
    [(0, 83, .5), (.5, 81, .5), (1, 79, .5), (1.5, 77, .5), (2, 74, 1), (3.5, 67, .5)],
    [(0, 69, .5), (.5, 72, .5), (1, 77, .5), (1.5, 81, .5), (2, 79, 1), (3, 76, 1)],
    [(0, 80, 1), (1, 83, .5), (1.5, 80, .5), (2, 76, 1), (3, 74, 1)],
    [(0, 72, .5), (.5, 76, .5), (1, 81, 1), (2, 78, .5), (2.5, 81, .5), (3, 84, 1)],
    [(0, 83, 1), (1, 81, .5), (1.5, 77, .5), (2, 74, .5), (2.5, 77, .5), (3, 79, .5), (3.5, 71, .5)],
]

# ボサノバの 3-2 クラーベ（2小節で1周）
CLAVE = [[0, 1.5, 3], [1, 2.5]]


def render():
    for bar in range(BARS):
        b0 = bar * 4
        chords = CHORDS[bar]
        half = 4 / len(chords)
        for k, (root, tones) in enumerate(chords):
            s = b0 + k * half
            # ベース：ルート → 5度
            fifth = root + 7
            if half == 4:
                play(s, bass(root, 1.5))
                play(s + 1.5, bass(fifth, .5))
                play(s + 2, bass(fifth, 1.5))
                play(s + 3.5, bass(root, .5))
            else:
                play(s, bass(root, 1.5))
                play(s + 1.5, bass(fifth, .5))
            # エレピ：ボサノバ風の刻み
            hits = [(0, 1.0), (1.5, 0.8), (2.5, 1.2)] if half == 4 else [(0, 1.0), (1.5, 0.45)]
            for off, dur in hits:
                for n in tones:
                    play(s + off, epiano(n, dur, 0.8 if off else 1.0))
        for beat, note, dur in MELODY[bar]:
            play(b0 + beat, marimba(note, dur, 1.0 if beat % 1 == 0 else 0.85))
        # ドラム
        play(b0, kick())
        play(b0 + 2, kick())
        for off in CLAVE[bar % 2]:
            play(b0 + off, rim())
        for e in range(8):
            play(b0 + e * .5, shaker(e % 2 == 1))


def write(path):
    peak = max(abs(v) for v in buf) or 1.0
    gain = 0.8 / peak
    data = array.array("h", (int(max(-1.0, min(1.0, v * gain)) * 32000) for v in buf))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print(f"wrote {path}: {LENGTH / RATE:.1f}s, peak before normalize={peak:.2f}")


if __name__ == "__main__":
    render()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    write(os.path.join(root, "audio", "bgm_bistro.wav"))
