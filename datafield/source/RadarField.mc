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
// A background service downloads a small rain GRID (see RadarServiceDelegate);
// this field draws a region of it as colored cells + city/GPS markers. The view
// is ZOOMED to ~VIEW_HALF_KM around the current GPS location, in true km scale.
// Use the single-field (full-screen) data layout for a usable size.
class RadarField extends WatchUi.DataField {

    const DEFAULT_HALF_KM = 75.0; // fallback range if the setting is unset
    const DEG = 0.0174533;        // pi/180

    // ARSO radar palette: index 0 (no rain) not drawn, 1..15 = light blue -> magenta.
    // Must match RAIN_RGB_TO_LEVEL in the proxy.
    const COLORS = [
        0x000000,
        0x085AFE, 0x008CFE, 0x00AEFD, 0x00C8FE, 0x04D883, 0x42EB42, 0x6CF900,
        0xB8FA00, 0xF9FA00, 0xFEC600, 0xFE8400, 0xFF3E01, 0xD30000, 0xB50303,
        0xCB00CC
    ];

    // Reference cities [lat, lon, label].
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

    // WGS84 corners of the radar data extent (matches the proxy crop).
    const NW_LON = 12.101924; const NW_LAT = 47.383315;
    const NE_LON = 17.412818; const NE_LAT = 47.385828;
    const SW_LON = 12.230101; const SW_LAT = 44.687306;
    const SE_LON = 17.289933; const SE_LAT = 44.689702;

    var _hasFix; var _lat; var _lon;
    // Screen transform (set each draw): screen = center + (deg delta) * pxPerDeg.
    var _cLat; var _cLon; var _cx; var _cy; var _pxLon; var _pxLat; var _w; var _h;

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

    // (u,v) in the data extent -> (lat, lon), bilinear over the corner quad.
    function uvToLatLon(u, v) {
        var lat = (1.0 - v) * (NW_LAT + (NE_LAT - NW_LAT) * u) + v * (SW_LAT + (SE_LAT - SW_LAT) * u);
        var lon = (1.0 - u) * (NW_LON + (SW_LON - NW_LON) * v) + u * (NE_LON + (SE_LON - NE_LON) * v);
        return [lat, lon];
    }

    // (lat, lon) -> (u, v), iterative inverse of the bilinear quad.
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

    function sx(lon) { return _cx + ((lon - _cLon) * _pxLon).toNumber(); }
    function sy(lat) { return _cy + ((_cLat - lat) * _pxLat).toNumber(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(bg, bg);
        dc.clear();

        _w = dc.getWidth();
        _h = dc.getHeight();

        var grid = Application.Storage.getValue("grid");
        if (!(grid instanceof Lang.String)) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2, _h / 2, Graphics.FONT_XTINY, "waiting for radar...",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Parse "W\nH\nHH:MM\n<base64>".
        var n1 = grid.find("\n");
        var s1 = (n1 != null) ? grid.substring(n1 + 1, grid.length()) : null;
        var n2 = (s1 != null) ? s1.find("\n") : null;
        var s2 = (n2 != null) ? s1.substring(n2 + 1, s1.length()) : null;
        var n3 = (s2 != null) ? s2.find("\n") : null;
        if (n3 == null) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2, _h / 2, Graphics.FONT_XTINY, "bad data",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var gw = grid.substring(0, n1).toNumber();
        var gh = s1.substring(0, n2).toNumber();
        var gt = s2.substring(0, n3);
        var bytes = StringUtil.convertEncodedString(s2.substring(n3 + 1, s2.length()), {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });

        // --- Set up the zoomed, km-square screen transform centered on GPS -----
        _cLat = _hasFix ? _lat : 46.05;          // default Ljubljana if no fix
        _cLon = _hasFix ? _lon : 14.51;
        var halfKm = Application.Properties.getValue("viewHalfKm");
        if (halfKm == null || halfKm <= 0) { halfKm = DEFAULT_HALF_KM; }
        halfKm = halfKm.toFloat();

        var cosLat = Math.cos(_cLat * DEG);
        var scale = (_w < _h ? _w : _h) / (2.0 * halfKm);  // px per km
        _pxLon = 111.0 * cosLat * scale;          // px per degree lon
        _pxLat = 111.0 * scale;                   // px per degree lat
        _cx = _w / 2;
        _cy = _h / 2;

        // Limit the cell loop to the viewport's grid range.
        var dLat = halfKm / 111.0;
        var dLon = halfKm / (111.0 * cosLat);
        var gx0 = (mapUV(_cLat, _cLon - dLon)[0] * gw).toNumber() - 1;
        var gx1 = (mapUV(_cLat, _cLon + dLon)[0] * gw).toNumber() + 2;
        var gy0 = (mapUV(_cLat + dLat, _cLon)[1] * gh).toNumber() - 1;
        var gy1 = (mapUV(_cLat - dLat, _cLon)[1] * gh).toNumber() + 2;
        if (gx0 < 0) { gx0 = 0; }
        if (gy0 < 0) { gy0 = 0; }
        if (gx1 > gw) { gx1 = gw; }
        if (gy1 > gh) { gy1 = gh; }

        var cellPx = ((NE_LON - NW_LON) / gw) * _pxLon;
        var cpy = ((NW_LAT - SW_LAT) / gh) * _pxLat;
        if (cpy > cellPx) { cellPx = cpy; }
        var rectSz = (cellPx + 1.5).toNumber();
        if (rectSz < 2) { rectSz = 2; }
        var half = rectSz / 2;

        for (var gy = gy0; gy < gy1; gy += 1) {
            for (var gx = gx0; gx < gx1; gx += 1) {
                var k = gy * gw + gx;
                var b = bytes[k >> 1] & 0xFF;
                var v = ((k & 1) == 0) ? ((b >> 4) & 0x0F) : (b & 0x0F);
                if (v <= 0 || v >= COLORS.size()) { continue; }
                var ll = uvToLatLon((gx + 0.5) / gw, (gy + 0.5) / gh);
                var x = sx(ll[1]);
                var y = sy(ll[0]);
                if (x < -rectSz || x > _w || y < -rectSz || y > _h) { continue; }
                dc.setColor(COLORS[v], Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - half, y - half, rectSz, rectSz);
            }
        }

        drawCities(dc);
        if (_hasFix) { drawMarker(dc); }

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(2, 0, Graphics.FONT_XTINY, gt, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function drawCities(dc) {
        for (var i = 0; i < CITIES.size(); i += 1) {
            var c = CITIES[i];
            var x = sx(c[1]);
            var y = sy(c[0]);
            if (x < 0 || x > _w || y < 0 || y > _h) { continue; }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 2);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 1);
            dc.drawText(x + 3, y - 7, Graphics.FONT_XTINY, c[2], Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function drawMarker(dc) {
        var x = sx(_lon);
        var y = sy(_lat);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 4);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 2);
    }
}
