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
import re
import urllib.request

from PIL import Image, ImageSequence
import numpy as np

ANIM_URL = "https://meteo.arso.gov.si/uploads/probase/www/observ/radar/si0-rm-anim.gif"
LATEST_URL = "https://meteo.arso.gov.si/uploads/probase/www/observ/radar/si0-rm.gif"

OUT_DIR = "public"
FRAMES_DIR = os.path.join(OUT_DIR, "frames")

FRAMES_OUT = 4          # max frames kept (bounds the watch's memory use)
GRID_W, GRID_H = 144, 108  # rain-grid resolution for the data field
MAX_GRID_B64 = 5000        # payload cap; Background.exit() allows 8 KB

# Map (data) area inside the 821x660 image, as fractions (header bar + frame
# cropped off). Keep these in sync with the Garmin app's MAP_* constants.
MAP_LEFT, MAP_RIGHT = 0.010, 0.990
MAP_TOP, MAP_BOTTOM = 0.063, 0.989


def fetch_gif() -> Image.Image:
    req = urllib.request.Request(ANIM_URL, headers={"User-Agent": "radar-proxy/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return Image.open(io.BytesIO(r.read()))


def fetch_latest_frame():
    """Return (RGB image, "HH:MM") for ARSO's newest single radar frame.

    The GIF embeds its true observation time in a comment block
    (# InputFile: si0-YYYYMMDD-HHMM-...). Use that rather than the workflow's own
    clock: GitHub drops scheduled runs, so utcnow() can be an hour or more later
    than the radar data it is labelling, which makes stale data look fresh.
    """
    req = urllib.request.Request(LATEST_URL, headers={"User-Agent": "radar-proxy/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
    m = re.search(rb"si0-\d{8}-(\d{2})(\d{2})", raw)
    hhmm = m.group(1).decode() + ":" + m.group(2).decode() if m else "--:--"
    return Image.open(io.BytesIO(raw)).convert("RGB"), hhmm


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


def intensity_grid(rgb_frame: Image.Image, grid_w: int, grid_h: int):
    """Crop to the data extent and reduce to a grid_h x grid_w array of 0..15."""
    w, h = rgb_frame.size
    box = (int(MAP_LEFT * w), int(MAP_TOP * h), int(MAP_RIGHT * w), int(MAP_BOTTOM * h))
    arr = np.asarray(rgb_frame.crop(box))  # H x W x 3, uint8
    key = (arr[..., 0].astype(np.uint32) << 16) | (arr[..., 1].astype(np.uint32) << 8) | arr[..., 2]

    inten = np.zeros(key.shape, dtype=np.uint8)
    for (r, g, b), lvl in RAIN_RGB_TO_LEVEL.items():
        inten[key == ((r << 16) | (g << 8) | b)] = lvl

    # Max-pool down to the grid so small/intense cells still register.
    ph, pw = inten.shape
    out = np.zeros((grid_h, grid_w), dtype=np.uint8)
    for gy in range(grid_h):
        y0, y1 = gy * ph // grid_h, (gy + 1) * ph // grid_h
        for gx in range(grid_w):
            x0, x1 = gx * pw // grid_w, (gx + 1) * pw // grid_w
            block = inten[y0:max(y1, y0 + 1), x0:max(x1, x0 + 1)]
            out[gy, gx] = int(block.max()) if block.size else 0
    return out


def rle_encode(grid) -> bytes:
    """Row-major run-length encode to (count 1..255, value 0..15) byte pairs.

    Radar frames are very sparse, so this is far smaller than one nibble per
    cell -- which matters because the whole payload must fit through
    Background.exit() (8 KB) and into a 32 KB background process.
    """
    flat = grid.reshape(-1)
    out = bytearray()
    run_val = int(flat[0])
    run_len = 0
    for v in flat:
        v = int(v)
        if v == run_val and run_len < 255:
            run_len += 1
            continue
        out += bytes((run_len, run_val))
        run_val, run_len = v, 1
    out += bytes((run_len, run_val))
    return bytes(out)


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

    # The grid comes from ARSO's dedicated "latest frame" image together with its
    # embedded observation time, so the timestamp shown on the watch always
    # describes exactly the data being drawn.
    latest_img, radar_time = fetch_latest_frame()
    print("latest ARSO frame observed at %s UTC" % radar_time)

    # Encode it as an RLE grid, halving the resolution until the payload is
    # safely under MAX_GRID_B64 (so it always fits Background.exit()).
    gw, gh = GRID_W, GRID_H
    while True:
        grid = intensity_grid(latest_img, gw, gh)
        d = base64.b64encode(rle_encode(grid)).decode("ascii")
        if len(d) <= MAX_GRID_B64 or gw < 32:
            break
        print("grid %dx%d -> %d b64 chars, too big; halving" % (gw, gh, len(d)))
        gw, gh = gw // 2, gh // 2

    # Plain text: GitHub's raw host serves .json as text/plain, so the watch
    # parses this line format. Line 4 marks the encoding so a stale cached grid
    # in an older format can never be misparsed.
    with open(os.path.join(OUT_DIR, "grid.txt"), "w") as f:
        f.write("%d\n%d\n%s\nrle\n%s" % (gw, gh, radar_time, d))
    print("grid %dx%d, payload %d b64 chars" % (gw, gh, len(d)))

    print("wrote %d frames + grid %dx%d at %s" % (len(names), gw, gh, ts))


if __name__ == "__main__":
    main()
