#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate-chess-audio.py（小板凳象棋音频生成器）

生成原创、可重复构建的音频资产：
1. move_wood.wav：木质棋子落盘声。
2. bgm_guofeng.wav：原创中国五声音阶背景音乐，
   使用程序合成模拟古筝拨弦、笛子气息与低音古琴层。

不使用第三方采样，不包含受版权保护旋律。
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "client" / "games" / "chinese_chess" / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)

SAMPLE_RATE = 32000
TAU = math.tau
RNG = random.Random(20260930)


def clamp(v: float) -> float:
    return max(-1.0, min(1.0, v))


def write_mono(path: Path, samples: list[float], rate: int = SAMPLE_RATE) -> None:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        data = bytearray()
        for sample in samples:
            data += struct.pack("<h", int(clamp(sample) * 32767.0))
        wav.writeframes(data)


def write_stereo(path: Path, left: list[float], right: list[float], rate: int = SAMPLE_RATE) -> None:
    assert len(left) == len(right)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        data = bytearray()
        for l, r in zip(left, right):
            data += struct.pack("<hh", int(clamp(l) * 32767.0), int(clamp(r) * 32767.0))
        wav.writeframes(data)


def generate_move_sound() -> None:
    """模拟硬木棋子落在檀木棋盘上的短促落子声。"""
    duration = 0.22
    count = int(SAMPLE_RATE * duration)
    samples: list[float] = []

    # 三个木质共振峰叠加少量瞬态噪声。
    resonances = (410.0, 760.0, 1320.0)
    phases = [RNG.random() * TAU for _ in resonances]

    for i in range(count):
        t = i / SAMPLE_RATE
        impact = math.exp(-t * 34.0)
        body = math.exp(-t * 18.0)
        noise = (RNG.random() * 2.0 - 1.0) * impact * 0.26

        tone = 0.0
        for idx, frequency in enumerate(resonances):
            tone += math.sin(TAU * frequency * t + phases[idx]) * body / (idx + 1.25)

        # 很轻的低频“桌面”共振，让落子不显得像电子提示音。
        low = math.sin(TAU * 128.0 * t) * math.exp(-t * 12.0) * 0.22
        samples.append((noise + tone * 0.32 + low) * 0.82)

    write_mono(OUT / "move_wood.wav", samples)


PENTATONIC = {
    "D3": 146.83,
    "A3": 220.00,
    "D4": 293.66,
    "E4": 329.63,
    "F#4": 369.99,
    "A4": 440.00,
    "B4": 493.88,
    "D5": 587.33,
    "E5": 659.25,
    "F#5": 739.99,
    "A5": 880.00,
}


def add_pluck(
    left: list[float],
    right: list[float],
    start: float,
    duration: float,
    frequency: float,
    gain: float,
    pan: float,
) -> None:
    """模拟古筝拨弦：快速起音、多泛音、指数衰减。"""
    begin = int(start * SAMPLE_RATE)
    end = min(len(left), begin + int(duration * SAMPLE_RATE))
    phase2 = RNG.random() * TAU
    phase3 = RNG.random() * TAU

    for i in range(begin, end):
        t = (i - begin) / SAMPLE_RATE
        attack = min(1.0, t / 0.008)
        envelope = attack * math.exp(-t * 3.4)
        bend = 1.0 + 0.004 * math.exp(-t * 8.0)
        fundamental = math.sin(TAU * frequency * bend * t)
        harmonic2 = math.sin(TAU * frequency * 2.01 * t + phase2) * 0.32
        harmonic3 = math.sin(TAU * frequency * 3.98 * t + phase3) * 0.16
        pick = (RNG.random() * 2.0 - 1.0) * math.exp(-t * 28.0) * 0.08
        sample = (fundamental + harmonic2 + harmonic3 + pick) * envelope * gain

        l_gain = math.sqrt((1.0 - pan) * 0.5)
        r_gain = math.sqrt((1.0 + pan) * 0.5)
        left[i] += sample * l_gain
        right[i] += sample * r_gain


def add_dizi(
    left: list[float],
    right: list[float],
    start: float,
    duration: float,
    frequency: float,
    gain: float,
    pan: float,
) -> None:
    """模拟竹笛：柔和基频、少量高次泛音、5Hz左右揉音与微弱气息。"""
    begin = int(start * SAMPLE_RATE)
    end = min(len(left), begin + int(duration * SAMPLE_RATE))
    breath_seed = random.Random(int(start * 1000) + 17)

    for i in range(begin, end):
        t = (i - begin) / SAMPLE_RATE
        tail = duration - t
        attack = min(1.0, t / 0.09)
        release = min(1.0, max(0.0, tail / 0.18))
        envelope = attack * release
        vibrato = 1.0 + 0.0048 * math.sin(TAU * 5.15 * t)
        phase = TAU * frequency * vibrato * t
        tone = (
            math.sin(phase)
            + 0.22 * math.sin(phase * 2.01)
            + 0.08 * math.sin(phase * 3.02)
        )
        breath = (breath_seed.random() * 2.0 - 1.0) * 0.025
        sample = (tone * 0.46 + breath) * envelope * gain

        l_gain = math.sqrt((1.0 - pan) * 0.5)
        r_gain = math.sqrt((1.0 + pan) * 0.5)
        left[i] += sample * l_gain
        right[i] += sample * r_gain


def add_bass_qin(
    left: list[float],
    right: list[float],
    start: float,
    frequency: float,
    gain: float,
) -> None:
    """模拟古琴低弦作为节拍根音。"""
    begin = int(start * SAMPLE_RATE)
    duration = 2.4
    end = min(len(left), begin + int(duration * SAMPLE_RATE))

    for i in range(begin, end):
        t = (i - begin) / SAMPLE_RATE
        env = math.exp(-t * 2.1)
        sample = (
            math.sin(TAU * frequency * t)
            + 0.24 * math.sin(TAU * frequency * 2.0 * t)
        ) * env * gain
        left[i] += sample * 0.72
        right[i] += sample * 0.72


def generate_bgm() -> None:
    """生成约 27 秒的原创国风循环段。"""
    bpm = 86.0
    beat = 60.0 / bpm
    beats = 40
    duration = beats * beat
    total = int(duration * SAMPLE_RATE)
    left = [0.0] * total
    right = [0.0] * total

    # 古筝主型：D 宫调式五声音阶，旋律为原创固定序列。
    pluck_pattern = [
        "D4", "A4", "F#4", "E4",
        "D4", "E4", "F#4", "A4",
        "B4", "A4", "F#4", "E4",
        "D4", "F#4", "A4", "D5",
        "B4", "A4", "F#4", "E4",
        "D4", "E4", "A4", "B4",
        "D5", "B4", "A4", "F#4",
        "E4", "F#4", "E4", "D4",
        "A4", "F#4", "D4", "E4",
        "F#4", "A4", "E4", "D4",
    ]

    for idx, note in enumerate(pluck_pattern):
        start = idx * beat
        pan = -0.34 if idx % 2 == 0 else 0.28
        add_pluck(left, right, start, beat * 1.65, PENTATONIC[note], 0.22, pan)

        # 每半拍加一颗更轻的高音装饰，增强古筝颗粒感。
        if idx % 2 == 1:
            ornament = "D5" if idx % 4 == 1 else "A4"
            add_pluck(
                left, right,
                start + beat * 0.52,
                beat * 0.9,
                PENTATONIC[ornament],
                0.085,
                -pan,
            )

    # 竹笛长线旋律，留出呼吸空隙。
    dizi_phrases = [
        (2, 3.3, "A4"),
        (6, 2.8, "B4"),
        (10, 3.5, "D5"),
        (16, 3.0, "A4"),
        (21, 3.5, "E5"),
        (28, 3.0, "D5"),
        (34, 3.4, "A4"),
    ]
    for beat_index, beat_length, note in dizi_phrases:
        add_dizi(
            left,
            right,
            beat_index * beat,
            beat_length * beat,
            PENTATONIC[note],
            0.115,
            0.12,
        )

    # 古琴低音每四拍落一次，稳定整体节奏。
    bass_pattern = ["D3", "D3", "A3", "D3", "D3", "A3", "D3", "A3", "D3", "D3"]
    for bar, note in enumerate(bass_pattern):
        add_bass_qin(left, right, bar * beat * 4.0, PENTATONIC[note], 0.115)

    # 简易双延迟营造小空间混响，不依赖外部 DSP。
    delay_a = int(SAMPLE_RATE * 0.17)
    delay_b = int(SAMPLE_RATE * 0.31)
    for i in range(total):
        if i >= delay_a:
            left[i] += right[i - delay_a] * 0.12
            right[i] += left[i - delay_a] * 0.10
        if i >= delay_b:
            left[i] += left[i - delay_b] * 0.07
            right[i] += right[i - delay_b] * 0.07

    # 头尾短淡入淡出，使循环切换不突兀。
    fade = int(SAMPLE_RATE * 0.28)
    for i in range(fade):
        factor = i / max(1, fade - 1)
        left[i] *= factor
        right[i] *= factor
        tail = total - 1 - i
        left[tail] *= factor
        right[tail] *= factor

    peak = max(max(abs(v) for v in left), max(abs(v) for v in right), 1e-6)
    scale = 0.76 / peak
    left = [v * scale for v in left]
    right = [v * scale for v in right]
    write_stereo(OUT / "bgm_guofeng.wav", left, right)


if __name__ == "__main__":
    generate_move_sound()
    generate_bgm()
    print(f"Generated: {OUT / 'move_wood.wav'}")
    print(f"Generated: {OUT / 'bgm_guofeng.wav'}")
