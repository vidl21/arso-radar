using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Communications;
using Toybox.Position;
using Toybox.Timer;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;
using Toybox.PersistedContent;

// Full-screen ARSO weather-radar view for the Garmin Edge 530.
//
// Fetches a pre-split radar loop from your GitHub-Actions proxy:
//   manifest.json -> list of frame PNGs -> each fetched as a bitmap.
// This shows the full ~1-hour loop immediately, instead of building it on-device.
// Requires a phone with internet connected over Bluetooth.
class RadarView extends WatchUi.View {

    // *** EDIT THIS *** to your proxy's gh-pages raw base URL (trailing slash):
    //   https://raw.githubusercontent.com/<USER>/<REPO>/gh-pages/
    const PROXY_BASE = "https://raw.githubusercontent.com/vidl21/arso-radar/gh-pages/";

    const REFRESH_MS   = 300000;  // 5 min — re-fetch the manifest
    const ANIM_MS      = 350;     // ms per frame while looping
    const HOLD_TICKS   = 4;       // pause on the newest frame
    const FRAME_MAX_W  = 220;     // cap fetched frame width (bounds memory)

    // Geo-calibration. Frames are the full 821x660 image (LCC). The map area
    // sits inside a header bar + thin frame; nudge these if the marker is off.
    const MAP_LEFT   = 0.010; const MAP_RIGHT  = 0.990;
    const MAP_TOP    = 0.063; const MAP_BOTTOM = 0.989;
    const NW_LON = 12.101924; const NW_LAT = 47.383315;
    const NE_LON = 17.412818; const NE_LAT = 47.385828;
    const SW_LON = 12.230101; const SW_LAT = 44.687306;
    const SE_LON = 17.289933; const SE_LAT = 44.689702;

    var _frames;        // Array of bitmaps (oldest -> newest)
    var _names;         // frame paths from the manifest
    var _expected;      // expected frame count
    var _loadIndex;     // next frame index to fetch
    var _loading;       // a request is in flight
    var _lastCode;      // last response code
    var _ts;            // proxy timestamp string ("YYYY-MM-DDTHH:MMZ")
    var _animIndex;
    var _holdCount;
    var _hasFix; var _lat; var _lon;
    var _fetchTimer; var _animTimer;

    function initialize() {
        View.initialize();
        _frames = [];
        _names = [];
        _expected = 0;
        _loadIndex = 0;
        _loading = false;
        _lastCode = 0;
        _ts = null;
        _animIndex = 0;
        _holdCount = 0;
        _hasFix = false;
        _lat = 0.0;
        _lon = 0.0;
    }

    function onShow() {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        if (_fetchTimer == null) {
            _fetchTimer = new Timer.Timer();
            _fetchTimer.start(method(:onFetchTimer), REFRESH_MS, true);
        }
        if (_animTimer == null) {
            _animTimer = new Timer.Timer();
            _animTimer.start(method(:onAnimTimer), ANIM_MS, true);
        }
        pollPosition();
        fetchManifest();
    }

    function onHide() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if (_fetchTimer != null) { _fetchTimer.stop(); _fetchTimer = null; }
        if (_animTimer != null)  { _animTimer.stop();  _animTimer = null; }
    }

    function onFetchTimer() as Void { fetchManifest(); }

    function pollPosition() as Void {
        var info = Position.getInfo();
        if (info != null && info has :position && info.position != null) {
            var deg = info.position.toDegrees();
            if (deg[0] != 0.0 || deg[1] != 0.0) {
                _lat = deg[0]; _lon = deg[1]; _hasFix = true;
            }
        }
    }

    function onPosition(info as Position.Info) as Void {
        if (info has :position && info.position != null) {
            var deg = info.position.toDegrees();
            _lat = deg[0]; _lon = deg[1]; _hasFix = true;
            WatchUi.requestUpdate();
        }
    }

    function onAnimTimer() as Void {
        pollPosition();
        var n = _frames.size();
        if (n < 2) { WatchUi.requestUpdate(); return; }
        if (_holdCount > 0) { _holdCount -= 1; return; }
        _animIndex += 1;
        if (_animIndex >= n) { _animIndex = 0; }
        if (_animIndex == n - 1) { _holdCount = HOLD_TICKS; }
        WatchUi.requestUpdate();
    }

    // --- Download pipeline ---------------------------------------------------
    function fetchManifest() as Void {
        if (_loading) { return; }
        var settings = System.getDeviceSettings();
        if (settings has :phoneConnected && !settings.phoneConnected) {
            _lastCode = -1000;
            WatchUi.requestUpdate();
            return;
        }
        var params = { "t" => Time.now().value() };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(PROXY_BASE + "manifest.json", params, options, method(:onManifest));
    }

    function onManifest(code as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        _lastCode = code;
        if (code == 200 && data != null && data instanceof Lang.Dictionary && data.hasKey("frames")) {
            _names = data["frames"];
            _expected = data["count"];
            _ts = data["ts"];
            _frames = [];          // drop old frames before loading new (bounds memory)
            _animIndex = 0;
            _loadIndex = 0;
            fetchNextFrame();
        }
        WatchUi.requestUpdate();
    }

    function fetchNextFrame() as Void {
        if (_loadIndex >= _names.size()) { _loading = false; return; }
        _loading = true;
        var url = PROXY_BASE + _names[_loadIndex];
        var params = { "t" => Time.now().value() };
        var options = {
            :maxWidth => FRAME_MAX_W,
            :maxHeight => System.getDeviceSettings().screenHeight,
            :dithering => Communications.IMAGE_DITHERING_NONE
        };
        Communications.makeImageRequest(url, params, options, method(:onFrame));
    }

    function onFrame(code as Lang.Number, data as Graphics.BitmapReference or WatchUi.BitmapResource or Null) as Void {
        _lastCode = code;
        if (code == 200 && data != null) {
            _frames.add(data);
            _animIndex = _frames.size() - 1;
        }
        _loadIndex += 1;
        WatchUi.requestUpdate();
        fetchNextFrame();          // continue the chain
    }

    // --- Rendering -----------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var barH = 22;
        var areaH = h - barH;
        var n = _frames.size();

        if (n > 0) {
            var idx = _animIndex;
            if (idx >= n) { idx = n - 1; }
            var frame = _frames[idx];
            var iw = frame.getWidth();
            var ih = frame.getHeight();
            var imgX = (w - iw) / 2;
            var imgY = (areaH - ih) / 2;
            if (imgY < 0) { imgY = 0; }
            dc.drawBitmap(imgX, imgY, frame);
            if (_hasFix) { drawMarker(dc, imgX, imgY, iw, ih); }
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var msg = (_lastCode == -1000) ? "No phone"
                    : (_lastCode != 0 && _lastCode != 200) ? "Err " + _lastCode.toString()
                    : "Loading radar...";
            dc.drawText(w / 2, areaH / 2, Graphics.FONT_SMALL, msg,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        drawStatusBar(dc, w, h, barH, n);
    }

    function computeUV() {
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
        return [u, v];
    }

    function drawMarker(dc, imgX, imgY, iw, ih) {
        var uv = computeUV();
        var u = uv[0]; var v = uv[1];
        if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) { return; }
        var fx = MAP_LEFT + u * (MAP_RIGHT - MAP_LEFT);
        var fy = MAP_TOP + v * (MAP_BOTTOM - MAP_TOP);
        var sx = imgX + (fx * iw).toNumber();
        var sy = imgY + (fy * ih).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 5);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 3);
        dc.setPenWidth(1);
        dc.drawLine(sx - 8, sy, sx + 8, sy);
        dc.drawLine(sx, sy - 8, sx, sy + 8);
    }

    function drawStatusBar(dc, w, h, barH, n) {
        var y = h - barH;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_DK_GRAY);
        dc.fillRectangle(0, y, w, barH);

        var left;
        if (_lastCode == -1000) {
            left = "No phone";
        } else if (_loading) {
            left = "Updating " + n.toString() + "/" + _expected.toString();
        } else if (_lastCode != 0 && _lastCode != 200) {
            left = "Err " + _lastCode.toString();
        } else if (n > 0) {
            left = hhmm() + "  " + (_animIndex + 1).toString() + "/" + n.toString();
        } else {
            left = "--:--";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(4, y + barH / 2, Graphics.FONT_XTINY, left,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var right = _hasFix ? "GPS" : "No GPS";
        dc.setColor(_hasFix ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 4, y + barH / 2, Graphics.FONT_XTINY, right,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Extract HH:MM from the proxy timestamp "YYYY-MM-DDTHH:MMZ".
    function hhmm() {
        if (_ts != null && _ts.length() >= 16) {
            return _ts.substring(11, 16);
        }
        return "--:--";
    }
}
