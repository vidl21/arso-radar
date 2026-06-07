# Weather Radar — Garmin Edge 530

A full-screen Connect IQ app that shows the ARSO (Slovenia) precipitation radar
as a short looping animation and marks your current GPS position on it.

- Downloads the latest radar frame every **5 minutes**, keeps the last **6**, and
  cycles them as a loop (~30 min of history). Press **Start/Enter** to fetch now.
- A red dot with a white halo + crosshair marks your live GPS location.
- Bottom status bar shows the newest frame's time, the frame counter (e.g.
  `3/6`), and GPS / connection state.

## How it works (and its limits)

- **Source image:** the *latest single frame*
  `https://meteo.arso.gov.si/uploads/probase/www/observ/radar/si0-rm.gif`
  (821×660, Lambert Conformal Conic). ARSO only publishes this static frame plus
  a pre-combined animated GIF — there are no individually addressable frames, and
  Garmin's image proxy can't split an animated GIF on-device.
- **The loop is built on-device:** because of the above, the app accumulates
  frames itself while running. On open you start with 1 frame and build up to 6
  over ~25–30 min; it can't show the hour *before* you opened the app. Frames are
  held in memory only (not saved between launches).
- **Needs a connected phone:** the Edge 530 has no WiFi/cellular. Images are
  fetched over Bluetooth through the Garmin Connect app on your phone, which
  must have internet. No phone → the bar shows "No phone".

To tune the loop, edit the constants at the top of
[`source/RadarView.mc`](source/RadarView.mc): `FETCH_MS` (download cadence),
`MAX_FRAMES` (history length / memory use), `ANIM_MS` (loop speed).

## Build

```bash
./build.sh          # produces WeatherRadar.prg
./build.sh run      # also launches the simulator and loads the app
```

Or directly:

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$SDK/bin/monkeyc" -f monkey.jungle -d edge530 -o WeatherRadar.prg -y developer_key
```

## Install on the device (sideload)

1. Connect the Edge 530 by USB (it mounts as a drive).
2. Copy `WeatherRadar.prg` into the device's `GARMIN/Apps/` folder.
3. Eject and unplug. The app appears under
   **Activity Profiles / Apps / Connect IQ** (or the IQ menu).

> Sideloaded apps require a `developer_key`. For wider distribution, submit the
> app to the Connect IQ Store instead.

## GPS marker calibration

The marker position is derived from the published WGS84 corner coordinates of
the radar image and four inset fractions describing where the map sits inside
the picture (it has a black header bar and a thin gray frame). If your marker
sits slightly off your true location, tweak these constants near the top of
[`source/RadarView.mc`](source/RadarView.mc) and rebuild:

```
MAP_LEFT, MAP_RIGHT, MAP_TOP, MAP_BOTTOM   // map rectangle inside the image
NW_*/NE_*/SW_*/SE_*                        // corner lon/lat (usually leave as-is)
```

## Project layout

```
manifest.xml                 # app id, edge530 product, permissions
monkey.jungle                # build config
resources/strings            # app name
resources/drawables          # launcher icon
source/RadarApp.mc           # entry point
source/RadarView.mc          # fetch + render + GPS overlay
source/RadarDelegate.mc      # button input (refresh / exit)
```
