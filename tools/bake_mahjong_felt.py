"""Bake the periodic, linear pile data used by club_felt.gdshader (NumPy, Pillow)."""

from pathlib import Path

import numpy as np
from PIL import Image


SIZE = 1024
PATCH_MM = 256.0
OUTPUT = (Path(__file__).resolve().parents[1] / "client/games/mahjong/guiyang/assets"
          / "models/textures/T_Mahjong_Felt_Pile.png")


def blur_wrap(field, radius):
    fy = np.fft.fftfreq(SIZE)[:, None]
    fx = np.fft.rfftfreq(SIZE)
    kernel = np.exp(-2 * np.pi**2 * radius**2 * (fx**2 + fy**2))
    return np.fft.irfft2(np.fft.rfft2(field) * kernel, s=field.shape, axes=(0, 1))


def unit_field(field):
    return (field - field.mean()) / field.std()


def strand_layer(rng, lay, count, length_mm, width_mm, angle_spread):
    """Deposit tapered, gently curved fiber bundles across both periodic boundaries."""
    x, y = rng.uniform(0, SIZE, (2, count))
    angle = lay[y.astype(int), x.astype(int)] + rng.normal(0, angle_spread, count)
    length = rng.uniform(*length_mm, count) * SIZE / PATCH_MM
    curl = rng.normal(0, 0.12, count) * length
    along = np.linspace(-1, 1, int(np.ceil(length.max())) | 1)[:, None]
    arc = (1 - along**2) * curl
    dx = 0.5 * length * along
    u = x + dx * np.cos(angle) - arc * np.sin(angle)
    v = y + dx * np.sin(angle) + arc * np.cos(angle)
    ix, iy = np.floor(u).astype(int), np.floor(v).astype(int)
    weight = (1 - along**2) * rng.uniform(0.6, 1.4, count)
    field = np.zeros(SIZE * SIZE)
    for oy in (0, 1):
        for ox in (0, 1):
            indices = ((iy + oy) % SIZE) * SIZE + (ix + ox) % SIZE
            sample = weight * (1 - abs(u - ix - ox)) * (1 - abs(v - iy - oy))
            field += np.bincount(indices.ravel(), sample.ravel(), minlength=field.size)
    blurred = blur_wrap(field.reshape(SIZE, SIZE), width_mm * SIZE / PATCH_MM)
    return np.tanh(unit_field(blurred) / 1.8)


def main():
    rng = np.random.default_rng(1843)
    brush = unit_field(blur_wrap(rng.normal(size=(SIZE, SIZE)), 49))
    lay = 0.35 + 0.95 * np.tanh(brush)
    tufts = strand_layer(rng, lay, 13500, (3.8, 8.0), 0.45, 0.48)
    fibers = strand_layer(rng, lay, 63000, (1.6, 4.5), 0.17, 0.85)
    height_mm = 0.22 * tufts + 0.075 * fibers
    slopes = [(np.roll(height_mm, -1, axis) - np.roll(height_mm, 1, axis))
              / (2 * PATCH_MM / SIZE) for axis in (1, 0)]
    # RG are signed surface gradients, B is pile density and A is local nap angle.
    channels = [*slopes, 0.72 * tufts + 0.28 * fibers, (lay - 0.35) / 0.95]
    packed = np.rint((np.clip(np.stack(channels, axis=2), -1, 1) * 0.5 + 0.5) * 255)
    Image.fromarray(packed.astype(np.uint8)).save(OUTPUT)


if __name__ == "__main__":
    main()
