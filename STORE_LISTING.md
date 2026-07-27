# Connect IQ Store listings

Ready-to-paste text for the developer dashboard. Two separate apps.

---

## App 1 — Weather Radar  (full app, `WeatherRadar.iq`)

**Type:** Device app (Edge 530) · **Category:** Cycling · **Price:** Free

**Short description (tagline):**
Live Slovenia (ARSO) precipitation radar with your GPS position, animated on your Edge 530.

**Full description:**
Weather Radar shows the latest ARSO (Slovenian Environment Agency) precipitation
radar right on your Edge 530, so you can see where the rain is before and during
your ride.

• Animated radar loop — cycles through the most recent radar frames (~20–30 min of
  history) so you can see how the rain is moving.
• Your live GPS position is marked on the map.
• Full-screen image, refreshed automatically every few minutes.
• Manual refresh with the Start/Enter button.
• Clear status bar: frame counter, timestamp, and GPS / phone-connection state.

How it works: the app fetches radar frames over Bluetooth through the Garmin
Connect app on your phone, so it needs a phone with an internet connection nearby.
It covers Slovenia and the surrounding region (the ARSO si0 radar domain).

Radar imagery © ARSO – meteo.arso.gov.si. This is an unofficial app and is not
affiliated with or endorsed by ARSO.

**Requirements:**
- Garmin Edge 530
- Smartphone with the Garmin Connect app and an internet connection

**Keywords:** radar, weather, rain, precipitation, ARSO, Slovenia, vreme, dež

---

## App 2 — Weather Radar Field  (data field, `WeatherRadarField.iq`)

**Type:** Data field (Edge 530) · **Category:** Cycling · **Price:** Free

**Short description (tagline):**
A data-screen field showing live ARSO rain radar, zoomed around your location.

**Full description:**
Weather Radar Field puts a live precipitation map right on one of your activity
data screens, so you can glance at the rain without leaving your ride data.

• Live ARSO (Slovenia) rain radar drawn as a colored intensity map, using the
  official radar color scale (light blue → red → magenta).
• Zoomed and centered on your current GPS location, in true-to-scale kilometres.
• Adjustable map range — choose how far around you to show (40–150 km, or the
  whole region) in the app settings.
• Reference markers for major cities (Ljubljana, Maribor, Celje, Kranj, Koper,
  Novo mesto, Murska Sobota, Nova Gorica) plus your own position.
• Updates automatically in the background.

Best used on a single-field (full-screen) data page. Because Connect IQ data
fields cannot display web images, the radar is shown as a colored grid rather than
the raw radar picture; for the full radar image use the companion "Weather Radar"
app.

How it works: a background service fetches a compact radar grid over Bluetooth via
the Garmin Connect app on your phone, so it needs a phone with internet nearby.

Radar data © ARSO – meteo.arso.gov.si. Unofficial app, not affiliated with ARSO.

**Setup tip:** add it via Activity Profiles → Data Screens → Connect IQ, and set
the "Map range" in the app's settings (Garmin Connect Mobile → the app → Settings).

**Requirements:**
- Garmin Edge 530
- Smartphone with the Garmin Connect app and an internet connection

**Keywords:** radar, weather, rain, data field, ARSO, Slovenia, vreme, dež, map

---

### Notes for submission
- Screenshots are required — capture from the simulator (File → Screen Shot) or the device.
- Both apps must be signed with the same `developer_key` you used (keep it backed up).
- Consider linking each app to the other as a "companion" in the listing.
