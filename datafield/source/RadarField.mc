using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Position;
using Toybox.Application;
using Toybox.StringUtil;
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

    // Geo-calibration: the grid covers the radar data extent (already cropped by
    // the proxy), so (u,v) in [0,1] maps straight onto the grid.
    const NW_LON = 12.101924; const NW_LAT = 47.383315;
    const NE_LON = 17.412818; const NE_LAT = 47.385828;
    const SW_LON = 12.230101; const SW_LAT = 44.687306;
    const SE_LON = 17.289933; const SE_LAT = 44.689702;

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
                var v = bytes[gy * gw + gx] & 0xFF;
                if (v > 0 && v < COLORS.size()) {
                    dc.setColor(COLORS[v], Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle((gx * cw).toNumber(), (gy * ch).toNumber(),
                        (cw + 1).toNumber(), (ch + 1).toNumber());
                }
            }
        }

        if (_hasFix) {
            drawMarker(dc, w, h);
        }

        // Timestamp, top-left.
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(2, 0, Graphics.FONT_XTINY, gt, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function drawMarker(dc, w, h) {
        var latNAvg = (NW_LAT + NE_LAT) / 2.0;
        var latSAvg = (SW_LAT + SE_LAT) / 2.0;
        var v = (latNAvg - _lat) / (latNAvg - latSAvg);
        var u = 0.5;
        for (var i = 0; i < 4; i += 1) {
            var lonL = NW_LON + (SW_LON - NW_LON) * v;
            var lonR = NE_LON + (SE_LON - NE_LON) * v;
            u = (_lon - lonL) / (lonR - lonL);
            var latT = NW_LAT + (NE_LAT - NW_LAT) * u;
            var latB = SW_LAT + (SE_LAT - SW_LAT) * u;
            v = (latT - _lat) / (latT - latB);
        }
        if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) { return; }
        var sx = (u * w).toNumber();
        var sy = (v * h).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 4);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 2);
    }
}
