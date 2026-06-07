#!/usr/bin/env python3
"""
ARSO radar proxy processor.

Downloads the animated radar GIF and produces, into ./public:
  - frames/NN.png      : up to FRAMES_OUT recent frames (00 = oldest)
  - manifest.json      : { count, ts, frames: [...] }   (for the full app)
  - grid.json          : { w, h, t, d }  (for the data field)

`d` is a base64-encoded byte string of W*H intensity values (0..7), row-major,
top-left first, covering the radar's data extent (header/legend cropped off).

Run on GitHub Actions every ~5 min; the watch fetches the static output.
"""

import base64
import io
import json
import os
import datetime
import urllib.request

from PIL import Image, ImageSequence
import numpy as np

ANIM_URL = "https://meteo.arso.gov.si/uploads/probase/www/observ/radar/si0-rm-anim.gif"

OUT_DIR = "public"
FRAMES_DIR = os.path.join(OUT_DIR, "frames")

FRAMES_OUT = 4          # max frames kept (bounds the watch's memory use)
GRID_W, GRID_H = 32, 24 # rain-grid resolution for the data field

# Map (data) area inside the 821x660 image, as fractions (header bar + frame
# cropped off). Keep these in sync with the Garmin app's MAP_* constants.
MAP_LEFT, MAP_RIGHT = 0.010, 0.990
MAP_TOP, MAP_BOTTOM = 0.063, 0.989


def fetch_gif() -> Image.Image:
    req = urllib.request.Request(ANIM_URL, headers={"User-Agent": "radar-proxy/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return Image.open(io.BytesIO(r.read()))


def extract_frames(gif: Image.Image):
    # ImageSequence handles GIF frame disposal/compositing correctly.
    frames = []
    for frame in ImageSequence.Iterator(gif):
        frames.append(frame.convert("RGB").copy())
    return frames


def dedup(frames):
    # Drop consecutive identical frames (the animation repeats the last frame to
    # create a pause before looping, which otherwise gives duplicate frames).
    out = []
    prev = None
    for f in frames:
        b = f.tobytes()
        if b != prev:
            out.append(f)
            prev = b
    return out


def intensity_grid(rgb_frame: Image.Image):
    """Crop to the data extent and reduce to a GRID_W x GRID_H array of 0..7."""
    w, h = rgb_frame.size
    box = (int(MAP_LEFT * w), int(MAP_TOP * h), int(MAP_RIGHT * w), int(MAP_BOTTOM * h))
    crop = rgb_frame.crop(box)
    arr = np.asarray(crop).astype(np.float32) / 255.0  # H x W x 3

    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)

    # Hue in degrees
    hue = np.zeros_like(mx)
    delta = mx - mn + 1e-6
    mask = mx == r
    hue[mask] = (60 * ((g - b) / delta) % 360)[mask]
    mask = mx == g
    hue[mask] = (60 * ((b - r) / delta) + 120)[mask]
    mask = mx == b
    hue[mask] = (60 * ((r - g) / delta) + 240)[mask]

    # Classify each pixel to an intensity 0..7 by hue (blue=low -> red/magenta=high)
    inten = np.zeros(hue.shape, dtype=np.uint8)
    colored = (sat >= 0.25) & (mx >= 0.25)
    h_ = hue
    inten[colored & (h_ >= 200) & (h_ < 260)] = 1   # blue
    inten[colored & (h_ >= 170) & (h_ < 200)] = 2   # cyan
    inten[colored & (h_ >= 90)  & (h_ < 170)] = 3   # green
    inten[colored & (h_ >= 60)  & (h_ < 90)]  = 4   # yellow-green
    inten[colored & (h_ >= 40)  & (h_ < 60)]  = 5   # yellow
    inten[colored & (h_ >= 20)  & (h_ < 40)]  = 6   # orange
    inten[colored & ((h_ < 20) | (h_ >= 300))] = 7  # red / magenta

    # Max-pool down to the grid so small cells still register.
    ph, pw = inten.shape
    out = np.zeros((GRID_H, GRID_W), dtype=np.uint8)
    for gy in range(GRID_H):
        y0, y1 = gy * ph // GRID_H, (gy + 1) * ph // GRID_H
        for gx in range(GRID_W):
            x0, x1 = gx * pw // GRID_W, (gx + 1) * pw // GRID_W
            block = inten[y0:max(y1, y0 + 1), x0:max(x1, x0 + 1)]
            out[gy, gx] = int(block.max()) if block.size else 0
    return out


def main():
    os.makedirs(FRAMES_DIR, exist_ok=True)
    gif = fetch_gif()
    frames = dedup(extract_frames(gif))
    if not frames:
        raise SystemExit("no frames decoded")
    print("decoded %d distinct frames" % len(frames))

    selected = frames[-FRAMES_OUT:]          # most recent distinct frames
    ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ")

    names = []
    for i, fr in enumerate(selected):
        name = "frames/%02d.png" % i         # 00 = oldest of the window
        fr.save(os.path.join(OUT_DIR, name), optimize=True)
        names.append(name)

    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as f:
        json.dump({"count": len(names), "ts": ts, "frames": names}, f)

    grid = intensity_grid(selected[-1])      # newest frame
    d = base64.b64encode(grid.tobytes()).decode("ascii")
    with open(os.path.join(OUT_DIR, "grid.json"), "w") as f:
        json.dump({"w": GRID_W, "h": GRID_H, "t": ts[-6:-1], "d": d}, f)
    # Plain-text grid (GitHub's raw host serves .json as text/plain, so the watch
    # parses this line-based format instead): W \n H \n HH:MM \n base64
    with open(os.path.join(OUT_DIR, "grid.txt"), "w") as f:
        f.write("%d\n%d\n%s\n%s" % (GRID_W, GRID_H, ts[-6:-1], d))

    print("wrote %d frames + grid %dx%d at %s" % (len(names), GRID_W, GRID_H, ts))


if __name__ == "__main__":
    main()
