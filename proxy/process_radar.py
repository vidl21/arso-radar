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
GRID_W, GRID_H = 144, 108  # rain-grid resolution for the data field (W*H must be even)

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


# ARSO radar palette -> intensity level 1..15 (light blue -> magenta). The GIF
# pixels are exactly these colors, so we match them directly. Must stay in sync
# with the COLORS table in the data field.
RAIN_RGB_TO_LEVEL = {
    (8, 90, 254): 1,  (0, 140, 254): 2,  (0, 174, 253): 3,  (0, 200, 254): 4,
    (4, 216, 131): 5, (66, 235, 66): 6,  (108, 249, 0): 7,  (184, 250, 0): 8,
    (249, 250, 0): 9, (254, 198, 0): 10, (254, 132, 0): 11, (255, 62, 1): 12,
    (211, 0, 0): 13,  (181, 3, 3): 14,   (203, 0, 204): 15,
}


def intensity_grid(rgb_frame: Image.Image):
    """Crop to the data extent and reduce to a GRID_H x GRID_W array of 0..15."""
    w, h = rgb_frame.size
    box = (int(MAP_LEFT * w), int(MAP_TOP * h), int(MAP_RIGHT * w), int(MAP_BOTTOM * h))
    arr = np.asarray(rgb_frame.crop(box))  # H x W x 3, uint8
    key = (arr[..., 0].astype(np.uint32) << 16) | (arr[..., 1].astype(np.uint32) << 8) | arr[..., 2]

    inten = np.zeros(key.shape, dtype=np.uint8)
    for (r, g, b), lvl in RAIN_RGB_TO_LEVEL.items():
        inten[key == ((r << 16) | (g << 8) | b)] = lvl

    # Max-pool down to the grid so small/intense cells still register.
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

    grid = intensity_grid(selected[-1])      # newest frame, shape (H, W), values 0-7
    flat = grid.reshape(-1)
    # Pack two 4-bit cells per byte (even index -> high nibble) to halve payload.
    packed = ((flat[0::2].astype(np.uint16) << 4) | flat[1::2]).astype(np.uint8)
    d = base64.b64encode(packed.tobytes()).decode("ascii")
    with open(os.path.join(OUT_DIR, "grid.json"), "w") as f:
        json.dump({"w": GRID_W, "h": GRID_H, "t": ts[-6:-1], "packed": 1, "d": d}, f)
    # Plain-text grid (GitHub's raw host serves .json as text/plain, so the watch
    # parses this line-based format): W \n H \n HH:MM \n base64(packed nibbles)
    with open(os.path.join(OUT_DIR, "grid.txt"), "w") as f:
        f.write("%d\n%d\n%s\n%s" % (GRID_W, GRID_H, ts[-6:-1], d))
    print("grid %dx%d, payload %d b64 chars" % (GRID_W, GRID_H, len(d)))

    print("wrote %d frames + grid %dx%d at %s" % (len(names), GRID_W, GRID_H, ts))


if __name__ == "__main__":
    main()
