using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Position;
using Toybox.Application;
using Toybox.StringUtil;
using Toybox.Math;
using Toybox.Lang;

// ARSO rain radar as an Edge 530 DATA FIELD.
//
// Data fields can't fetch web content, so the picture is impossible here. Instead
// a background service downloads a tiny rain GRID (see RadarServiceDelegate) and
// this field draws it as colored cells + a GPS marker. Low-res by design.
// Use the single-field (full-screen) data layout for a usable size.
class RadarField extends WatchUi.DataField {

    // Intensity palette, index 0 (no rain) is not drawn.
    const COLORS = [0x000000, 0x66B3FF, 0x3377FF, 0x00CCCC, 0x00AA00, 0xFFFF00, 0xFF8000, 0xFF0000];

    // Reference cities [lat, lon, label] for orientation on the grid.
    const CITIES = [
        [46.056, 14.506, "LJ"],   // Ljubljana
        [46.554, 15.646, "MB"],   // Maribor
        [46.231, 15.260, "CE"],   // Celje
        [46.239, 14.356, "KR"],   // Kranj
        [45.548, 13.730, "KP"],   // Koper
        [45.804, 15.169, "NM"],   // Novo mesto
        [46.658, 16.166, "MS"],   // Murska Sobota
        [45.955, 13.648, "NG"]    // Nova Gorica
    ];

    // Geo-calibration: the grid covers the radar data extent (already cropped by
    // the proxy), so (u,v) in [0,1] maps straight onto the grid.
    const NW_LON = 12.101924; const NW_LAT = 47.383315;
    const NE_LON = 17.412818; const NE_LAT = 47.385828;
    const SW_LON = 12.230101; const SW_LAT = 44.687306;
    const SE_LON = 17.289933; const SE_LAT = 44.689702;

    // TEMP: set to false for production (shows a synthetic grid when no real data).
    const DEMO = false;

    var _hasFix; var _lat; var _lon;

    function initialize() {
        DataField.initialize();
        _hasFix = false;
        _lat = 0.0;
        _lon = 0.0;
    }

    // Read GPS each second (from the activity, or a direct poll as fallback).
    function compute(info as Activity.Info) as Void {
        if (info has :currentLocation && info.currentLocation != null) {
            var deg = info.currentLocation.toDegrees();
            _lat = deg[0]; _lon = deg[1]; _hasFix = true;
        } else {
            var pinfo = Position.getInfo();
            if (pinfo != null && pinfo has :position && pinfo.position != null) {
                var pdeg = pinfo.position.toDegrees();
                if (pdeg[0] != 0.0 || pdeg[1] != 0.0) {
                    _lat = pdeg[0]; _lon = pdeg[1]; _hasFix = true;
                }
            }
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (DEMO) { drawDemo(dc, w, h); return; }   // TEMP: always show demo grid

        var grid = Application.Storage.getValue("grid");
        if (!(grid instanceof Lang.String)) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY, "waiting for radar...",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Parse "W\nH\nHH:MM\n<base64>".
        var n1 = grid.find("\n");
        var s1 = (n1 != null) ? grid.substring(n1 + 1, grid.length()) : null;
        var n2 = (s1 != null) ? s1.find("\n") : null;
        var s2 = (n2 != null) ? s1.substring(n2 + 1, s1.length()) : null;
        var n3 = (s2 != null) ? s2.find("\n") : null;
        if (n1 == null || n2 == null || n3 == null) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY, "bad data",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var gw = grid.substring(0, n1).toNumber();
        var gh = s1.substring(0, n2).toNumber();
        var gt = s2.substring(0, n3);
        var d  = s2.substring(n3 + 1, s2.length());
        var bytes = StringUtil.convertEncodedString(d, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });

        // Cell size (cover the full field).
        var cw = w.toFloat() / gw;
        var ch = h.toFloat() / gh;
        for (var gy = 0; gy < gh; gy += 1) {
            for (var gx = 0; gx < gw; gx += 1) {
                var k = gy * gw + gx;                 // cells packed 2-per-byte
                var b = bytes[k >> 1] & 0xFF;
                var v = ((k & 1) == 0) ? ((b >> 4) & 0x0F) : (b & 0x0F);
                if (v > 0 && v < COLORS.size()) {
                    dc.setColor(COLORS[v], Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle((gx * cw).toNumber(), (gy * ch).toNumber(),
                        (cw + 1).toNumber(), (ch + 1).toNumber());
                }
            }
        }

        drawCities(dc, w, h);

        if (_hasFix) {
            drawMarker(dc, w, h);
        }

        // Timestamp, top-left.
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(2, 0, Graphics.FONT_XTINY, gt, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Map (lat, lon) to normalized grid coords (u, v) in [0,1] x [0,1].
    function mapUV(lat, lon) {
        var latNAvg = (NW_LAT + NE_LAT) / 2.0;
        var latSAvg = (SW_LAT + SE_LAT) / 2.0;
        var v = (latNAvg - lat) / (latNAvg - latSAvg);
        var u = 0.5;
        for (var i = 0; i < 4; i += 1) {
            var lonL = NW_LON + (SW_LON - NW_LON) * v;
            var lonR = NE_LON + (SE_LON - NE_LON) * v;
            u = (lon - lonL) / (lonR - lonL);
            var latT = NW_LAT + (NE_LAT - NW_LAT) * u;
            var latB = SW_LAT + (SE_LAT - SW_LAT) * u;
            v = (latT - lat) / (latT - latB);
        }
        return [u, v];
    }

    // TEMP demo: synthetic 96x72 storm pattern so the resolution + cities are
    // visible in the simulator without waiting for a background fetch.
    function drawDemo(dc, w, h) {
        var gw = 144; var gh = 108;
        var cw = w.toFloat() / gw; var ch = h.toFloat() / gh;
        for (var gy = 0; gy < gh; gy += 1) {
            for (var gx = 0; gx < gw; gx += 1) {
                var d1 = Math.sqrt((gx - 57) * (gx - 57) + (gy - 45) * (gy - 45));
                var v = (d1 < 30) ? (7 - (d1 / 4.5).toNumber()) : 0;
                var d2 = Math.sqrt((gx - 102) * (gx - 102) + (gy - 69) * (gy - 69));
                var v2 = (d2 < 20) ? (6 - (d2 / 3).toNumber()) : 0;
                if (v2 > v) { v = v2; }
                if (v > 0 && v < COLORS.size()) {
                    dc.setColor(COLORS[v], Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle((gx * cw).toNumber(), (gy * ch).toNumber(),
                        (cw + 1).toNumber(), (ch + 1).toNumber());
                }
            }
        }
        drawCities(dc, w, h);
        if (_hasFix) { drawMarker(dc, w, h); }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(2, 0, Graphics.FONT_XTINY, "DEMO 144x108", Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Small dots + 2-letter labels for the major cities.
    function drawCities(dc, w, h) {
        for (var i = 0; i < CITIES.size(); i += 1) {
            var c = CITIES[i];
            var uv = mapUV(c[0], c[1]);
            if (uv[0] < 0.0 || uv[0] > 1.0 || uv[1] < 0.0 || uv[1] > 1.0) { continue; }
            var sx = (uv[0] * w).toNumber();
            var sy = (uv[1] * h).toNumber();
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sx, sy, 2);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sx, sy, 1);
            dc.drawText(sx + 3, sy - 7, Graphics.FONT_XTINY, c[2], Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function drawMarker(dc, w, h) {
        var uv = mapUV(_lat, _lon);
        if (uv[0] < 0.0 || uv[0] > 1.0 || uv[1] < 0.0 || uv[1] > 1.0) { return; }
        var sx = (uv[0] * w).toNumber();
        var sy = (uv[1] * h).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 4);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 2);
    }
}
