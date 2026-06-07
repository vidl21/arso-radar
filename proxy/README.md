# Radar proxy (GitHub Actions, free)

Turns ARSO's animated radar GIF into watch-friendly static files, refreshed every
~5 minutes by a free GitHub Actions cron. No server to run.

## What it produces (on the `gh-pages` branch, in `public/`)

| File | For | Contents |
|---|---|---|
| `frames/00.png … NN.png` | full app | recent radar frames (00 = oldest) |
| `manifest.json` | full app | `{ count, ts, frames: [...] }` |
| `grid.json` | data field | `{ w, h, t, d }` — `d` = base64 of W×H intensity bytes (0–7) |

## One-time setup

1. Create a **public** GitHub repo (e.g. `arso-radar-proxy`) and push this
   project to it (the `proxy/` folder and `.github/workflows/radar.yml`).
2. In the repo: **Settings → Actions → General → Workflow permissions** →
   enable **Read and write permissions**.
3. Run it once: **Actions → "Update radar" → Run workflow**. After it finishes a
   `gh-pages` branch appears with the files above.
4. (Optional) **Settings → Pages → Source: gh-pages** if you prefer Pages URLs.

## Your output URLs

```
https://raw.githubusercontent.com/<USER>/<REPO>/gh-pages/manifest.json
https://raw.githubusercontent.com/<USER>/<REPO>/gh-pages/frames/00.png
https://raw.githubusercontent.com/<USER>/<REPO>/gh-pages/grid.json
```

Put your base URL into the Garmin apps:
- Full app: `PROXY_BASE` in [`../source/RadarView.mc`](../source/RadarView.mc)
- Data field: `GRID_URL` in [`../datafield/source/RadarServiceDelegate.mc`](../datafield/source/RadarServiceDelegate.mc)

## Notes / etiquette

- The cron is every 5 min (ARSO's update cadence). GitHub may run it a few
  minutes late — fine for radar.
- `force_orphan: true` keeps `gh-pages` at a single commit so image churn doesn't
  bloat the repo.
- Be polite to ARSO: don't lower the interval below 5 min.
