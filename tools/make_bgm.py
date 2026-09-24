#!/usr/bin/env python3
"""BGM「カフェの午後」を合成して audio/bgm_bistro.wav に書き出す。

外部ライブラリ不要（標準の Python 3 だけで動く）。
曲を変えたいときは、下の CHORDS（コード進行）や MELODY（メロディ）を書き換えて
    python3 tools/make_bgm.py
を実行し、Godot で開き直せば反映される。

構成: 76 BPM・4/4 拍子・16小節でループ（約50秒）
  ロデス風エレピのコード（トレモロつき） / 同じ音色のやわらかいリード・メロディ /
  丸いウッドベース / ブラシの軽いスネアだけ（2・4拍）。
  ボサノバ版（キック・クラーベ・シェイカー）より打楽器をぐっと減らし、
  メロディの音符も間引いて、カフェで静かに流れているくらいの落ち着きにしてある。
"""
import array
import math
import os
import random
import wave

RATE = 22050
BPM = 76
BEAT = 60.0 / BPM
BARS = 16
LENGTH = int(BARS * 4 * BEAT * RATE)
## 裏拍（8分音符の「と」）をこの分だけ遅らせて、もたついた（レイドバックな）ノリにする
SWING_BEATS = 0.09

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


def swing(beat):
    """8分音符の裏拍だけを少し遅らせる（メロディにだけ使う）"""
    eighth = beat * 2
    if abs(eighth - round(eighth)) < 1e-6 and int(round(eighth)) % 2 == 1:
        return beat + SWING_BEATS
    return beat


# ---------------------------------------------------------------- 楽器

def epiano_chord(note, dur_beats, vel=1.0):
    """ロデス風の電子ピアノ。ゆっくりしたトレモロ（音量のゆれ）で温かみを出す"""
    f = midi_hz(note)
    d = dur_beats * BEAT + 0.3

    def fn(t):
        a = min(1.0, t / 0.02)
        tremolo = 1.0 + 0.12 * math.sin(2 * math.pi * 4.5 * t)
        body = math.sin(2 * math.pi * f * t)
        body += math.sin(2 * math.pi * f * 2.01 * t) * 0.15 * math.exp(-t * 3.0)
        return body * a * tremolo * math.exp(-t * 1.1) * release(t, d, 0.15) * 0.05 * vel
    return d, fn


def epiano_lead(note, dur_beats, vel=1.0):
    """コードと同じ音色のメロディ用。マレットの打鍵音をほんの少しだけ足す"""
    f = midi_hz(note)
    d = min(1.8, dur_beats * BEAT + 0.7)

    def fn(t):
        a = min(1.0, t / 0.006)
        tremolo = 1.0 + 0.1 * math.sin(2 * math.pi * 5.0 * t + 1.0)
        click = 0.05 * math.exp(-t * 300.0)
        body = math.sin(2 * math.pi * f * t)
        body += math.sin(2 * math.pi * f * 2.0 * t) * 0.08 * math.exp(-t * 8.0)
        return (body * tremolo * math.exp(-t * 1.7) + click) * a * release(t, d, 0.12) * 0.085 * vel
    return d, fn


def bass(note, dur_beats):
    """丸みのあるウッドベース。アタックをやわらかくしてある"""
    f = midi_hz(note)
    d = dur_beats * BEAT

    def fn(t):
        a = min(1.0, t / 0.015)
        v = math.sin(2 * math.pi * f * t) + math.sin(2 * math.pi * f * 2 * t) * 0.2 * math.exp(-t * 6)
        return v * a * math.exp(-t * 1.8) * release(t, d, 0.06) * 0.28
    return d, fn


def brush(accent):
    """ブラシで軽くこするようなスネア。2・4拍にだけ添える"""
    state = [0.0]

    def fn(t):
        n = random.uniform(-1, 1)
        state[0] += (n - state[0]) * 0.3
        hp = n - state[0]
        env = min(1.0, t / 0.02) * math.exp(-t * 9.0)
        return hp * env * (0.06 if accent else 0.04)
    return 0.35, fn


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

# メロディ: 小節ごとに (拍, MIDIノート, 長さ[拍])。カフェらしく、間を空けて音数を絞ってある
MELODY = [
    [(0, 76, 1), (1.5, 74, .5), (2, 72, 1.5)],
    [(0, 69, .5), (.5, 72, .5), (1, 76, 1.5), (3, 74, 1)],
    [(0, 77, 1), (1.5, 74, .5), (2, 72, 1.5)],
    [(0, 71, 1.5), (2, 76, .5), (2.5, 74, .5), (3, 71, 1)],
    [(0, 76, .5), (.5, 79, .5), (1, 84, 1.5), (3, 79, 1)],
    [(0, 81, 1.5), (2, 72, 1), (3, 76, 1)],
    [(0, 74, 1), (1.5, 81, .5), (2, 79, 1.5)],
    [(0, 72, 2), (3, 76, 1)],
    [(0, 81, 1), (1.5, 77, .5), (2, 76, 1.5)],
    [(0, 79, 1.5), (2, 71, 1), (3, 74, 1)],
    [(0, 74, .5), (.5, 77, .5), (1, 84, 1.5), (3, 81, 1)],
    [(0, 83, 1), (1.5, 79, .5), (2, 74, 1.5)],
    [(0, 69, 1), (1.5, 77, .5), (2, 79, 1.5)],
    [(0, 80, 1.5), (2, 76, 1), (3, 74, 1)],
    [(0, 72, .5), (.5, 76, .5), (1, 84, 1.5), (3, 81, 1)],
    [(0, 83, 1.5), (2, 74, 1), (3, 71, 1)],
]


def render():
    for bar in range(BARS):
        b0 = bar * 4
        chords = CHORDS[bar]
        half = 4 / len(chords)
        for k, (root, tones) in enumerate(chords):
            s = b0 + k * half
            # ベース：ルート → 5度（長い音価でゆったりと）
            fifth = root + 7
            if half == 4:
                play(s, bass(root, 2.5))
                play(s + 2.5, bass(fifth, 1.5))
            else:
                play(s, bass(root, half))
            # エレピ：1拍目に長く鳴らし、途中でもう一度そっと押さえ直す（パッドのように）
            hits = [(0, half - 0.15, 1.0), (half * 0.5, half * 0.5, 0.55)] if half == 4 else [(0, half - 0.1, 1.0)]
            for off, dur, vel in hits:
                for n in tones:
                    play(s + off, epiano_chord(n, dur, vel))
        for beat, note, dur in MELODY[bar]:
            play(b0 + swing(beat), epiano_lead(note, dur, 1.0 if beat % 1 == 0 else 0.8))
        # 打楽器はブラシの軽いスネアだけ（2拍目・4拍目）
        play(b0 + 1, brush(True))
        play(b0 + 3, brush(False))


def write(path):
    peak = max(abs(v) for v in buf) or 1.0
    gain = 0.78 / peak
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
