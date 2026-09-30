#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
process-chess-move-sfx.py（象棋走棋音效增强）

输入：16-bit PCM WAV（单声道或立体声）
输出：16-bit PCM WAV

处理链：
1. 去直流偏移 + 60Hz 高通，清理低频杂讯。
2. 自动裁剪前后无效静音，保留木质衰减尾音。
3. 瞬态增强：叠加高频差分分量，让落子“咔嗒”更清楚。
4. 木质主体增强：叠加短时低频共振分量，增加厚度。
5. 轻度动态压缩 + tanh 软限幅，提升平均响度而不爆音。
6. 峰值归一化到 -1 dBFS，首尾淡入淡出避免点击噪声。
"""

from __future__ import annotations

import argparse
import math
import struct
import wave
from pathlib import Path


def clamp(v: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, v))


def read_pcm16(path: Path):
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()
        frames = wav.getnframes()
        if width != 2:
            raise RuntimeError(f"Only 16-bit PCM WAV is supported, got {width * 8}-bit")
        raw = wav.readframes(frames)
    values = struct.unpack("<" + "h" * (len(raw) // 2), raw)
    data = [[] for _ in range(channels)]
    for i, value in enumerate(values):
        data[i % channels].append(value / 32768.0)
    return channels, rate, data


def write_pcm16(path: Path, rate: int, channels_data):
    path.parent.mkdir(parents=True, exist_ok=True)
    channels = len(channels_data)
    frames = min(len(ch) for ch in channels_data)
    packed = bytearray()
    for i in range(frames):
        for ch in range(channels):
            value = int(clamp(channels_data[ch][i]) * 32767.0)
            packed += struct.pack("<h", value)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(packed)


def dc_remove(samples):
    if not samples:
        return samples[:]
    mean = sum(samples) / len(samples)
    return [x - mean for x in samples]


def high_pass(samples, rate: int, cutoff_hz: float = 60.0):
    """First-order RC high-pass."""
    if not samples:
        return []
    dt = 1.0 / rate
    rc = 1.0 / (2.0 * math.pi * cutoff_hz)
    alpha = rc / (rc + dt)
    out = [0.0] * len(samples)
    prev_x = samples[0]
    prev_y = 0.0
    for i, x in enumerate(samples):
        y = alpha * (prev_y + x - prev_x)
        out[i] = y
        prev_x = x
        prev_y = y
    return out


def low_pass(samples, rate: int, cutoff_hz: float = 1600.0):
    """First-order RC low-pass."""
    if not samples:
        return []
    dt = 1.0 / rate
    rc = 1.0 / (2.0 * math.pi * cutoff_hz)
    alpha = dt / (rc + dt)
    out = [0.0] * len(samples)
    y = samples[0]
    for i, x in enumerate(samples):
        y += alpha * (x - y)
        out[i] = y
    return out


def trim_silence(channels_data, rate: int, threshold_db: float = -52.0):
    threshold = 10.0 ** (threshold_db / 20.0)
    frames = min(len(ch) for ch in channels_data)
    envelope = [max(abs(ch[i]) for ch in channels_data) for i in range(frames)]
    active = [i for i, v in enumerate(envelope) if v >= threshold]
    if not active:
        return channels_data
    pre = int(rate * 0.006)
    post = int(rate * 0.085)
    start = max(0, active[0] - pre)
    end = min(frames, active[-1] + post + 1)
    return [ch[start:end] for ch in channels_data]


def enhance_channel(samples, rate: int):
    samples = high_pass(dc_remove(samples), rate, 60.0)

    # Transient enhancement: difference from a short low-pass envelope.
    smooth = low_pass(samples, rate, 1800.0)
    transient = [x - s for x, s in zip(samples, smooth)]

    # Wooden body: low-mid energy, decays quickly so it does not become boomy.
    body = low_pass(samples, rate, 520.0)
    body_gain = 0.30
    transient_gain = 0.42

    mixed = [
        x + transient_gain * t + body_gain * b
        for x, t, b in zip(samples, transient, body)
    ]

    # Light static compressor. Threshold ~= -15 dBFS, ratio about 2.4:1.
    threshold = 10.0 ** (-15.0 / 20.0)
    ratio = 2.4
    compressed = []
    for x in mixed:
        sign = -1.0 if x < 0.0 else 1.0
        a = abs(x)
        if a > threshold:
            a = threshold + (a - threshold) / ratio
        compressed.append(sign * a)

    # Add makeup gain and soft limiting.
    makeup = 1.85
    return [math.tanh(x * makeup * 1.25) / math.tanh(1.25) for x in compressed]


def apply_fades(channels_data, rate: int):
    frames = min(len(ch) for ch in channels_data)
    fade_in = min(frames, max(1, int(rate * 0.0015)))
    fade_out = min(frames, max(1, int(rate * 0.040)))
    for ch in channels_data:
        for i in range(fade_in):
            ch[i] *= i / max(1, fade_in - 1)
        for i in range(fade_out):
            idx = frames - 1 - i
            ch[idx] *= i / max(1, fade_out - 1)


def normalize_peak(channels_data, target_db: float = -1.0):
    peak = max((abs(v) for ch in channels_data for v in ch), default=0.0)
    if peak <= 1e-9:
        return channels_data
    target = 10.0 ** (target_db / 20.0)
    scale = target / peak
    return [[v * scale for v in ch] for ch in channels_data]


def stats(channels_data):
    values = [v for ch in channels_data for v in ch]
    if not values:
        return -999.0, -999.0
    peak = max(abs(v) for v in values)
    rms = math.sqrt(sum(v * v for v in values) / len(values))
    peak_db = 20.0 * math.log10(max(peak, 1e-12))
    rms_db = 20.0 * math.log10(max(rms, 1e-12))
    return peak_db, rms_db


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    channels, rate, source = read_pcm16(input_path)
    source_peak, source_rms = stats(source)

    trimmed = trim_silence(source, rate)
    enhanced = [enhance_channel(ch, rate) for ch in trimmed]
    apply_fades(enhanced, rate)
    enhanced = normalize_peak(enhanced, -1.0)
    out_peak, out_rms = stats(enhanced)

    write_pcm16(output_path, rate, enhanced)

    frames = min(len(ch) for ch in enhanced)
    print(f"input={input_path}")
    print(f"output={output_path}")
    print(f"channels={channels}")
    print(f"sample_rate={rate}")
    print(f"duration_before={len(source[0]) / rate:.4f}s")
    print(f"duration_after={frames / rate:.4f}s")
    print(f"peak_before={source_peak:.2f}dBFS rms_before={source_rms:.2f}dBFS")
    print(f"peak_after={out_peak:.2f}dBFS rms_after={out_rms:.2f}dBFS")


if __name__ == "__main__":
    main()
